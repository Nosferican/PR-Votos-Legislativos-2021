"""
    PRLeg :: Module

"""
module PRLeg

using Cascadia: Cascadia, parsehtml, Selector, HTMLNode, HTMLText, nodeText, getattr
using Dates: Date
using PDFIO: pdDocOpen, pdDocGetInfo, pdDocGetPageCount, pdDocGetPage, pdPageExtractText, pdDocClose
using DataFrames: DataFrame
using CSV: CSV
using Diana: GraphQLClient,
             HTTP.request, HTTP.URI
using JSON3: JSON3
using LibPQ: Connection, load!, execute, prepare

conn = Connection("dbname=postgres user=postgres password=postgres")


ENV["WEBDRIVER_HOST"] = get(ENV, "WEBDRIVER_HOST", "localhost")
ENV["WEBDRIVER_PORT"] = get(ENV, "WEBDRIVER_PORT", "4444")

const CLIENT = GraphQLClient("https://openstates.org/graphql",
                             )

const MESES = Dict(zip(["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
1:12))

function parse_vote(node::HTMLNode)
    votación = only(eachmatch(Selector("a"), node[1]))
    fecha = nodeText(votación)
    fecha = Date(parse(Int, match(r"\d{4}$", fecha).match),
                 MESES[match(r"(?<= de ).*(?= de )", fecha).match],
                 parse(Int, match(r"\d{1,2}", fecha).match))
    pdf = URI(scheme = "https", host = "senado.pr.gov", path = getattr(votación, "href"))
    número = parse(Int, nodeText(node[2]))
    asamblea = nodeText(node[3])
    sesión = nodeText(node[4])
    isfile(joinpath("data", "senado", "$fecha.pdf")) || download(string(pdf), joinpath("data", "senado", "$fecha.pdf"))
    doc = pdDocOpen(joinpath("data", "senado", "$fecha.pdf"))
    docinfo = pdDocGetInfo(doc)
    npage = pdDocGetPageCount(doc)
    data = DataFrame()
    io = IOBuffer()
    for i in 1:npage
        page = pdDocGetPage(doc, i)
        text = pdPageExtractText(io, page)
        text = String(take!(io))
        append!(data, parse_page(text))
    end
    close(io)
    CSV.write(joinpath("data", "senado", "$fecha.csv"), data)
    nothing
end

function parse_page(text)
    lns = split(text, '\n')
    lns = filter!(!isempty, strip.(lns))
    output = if lns[2] == "Resultado de la Votación para la Medida"
        tipo = if startswith(lns[3], "R. Conc. del S.")
            "RKS"
        elseif startswith(lns[3], "R. del S.")
            "RS"
        elseif startswith(lns[3], "P. del S.")
            "PS"
        elseif startswith(lns[3], "R. C. del S.")
            "RCS"
        elseif startswith(lns[3], "Nombramiento")
            "NM"
        elseif startswith(lns[3], "P. de la C.")
            "PC"
        elseif startswith(lns[3], "R. C. de la C.")
            "RCC"
        elseif startswith(lns[3], "R. Conc. de la C.")
            "RKC"
        else
            throw(ArgumentError("handle $(lns[3])"))
        end
        número = parse(Int, match(r"\d{4}", lns[3]).match)
        idx = findfirst(ln -> startswith(ln, "Resultado"), @view(lns[3:end])) + 2
        resultado = match(r"(Aprobada|Confirmado|Recibido|Derrotad[oa])", lns[idx]).match
        votación = if startswith(lns[idx + 1], "votada")
            0
        else
            parse(Int, match(r"(?<=en\sla\svotación\snúmero\s)\d+", lns[idx + 1]).match)
        end
        fecha = match(r"(\d{1,2}\sde\s\w+\sde\s\d{4})", lns[idx + 1]).match
        fecha = Date(parse(Int, match(r"\d{4}$", fecha).match),
                     MESES[match(r"(?<=\sde\s).*(?=\sde\s)", fecha).match],
                     parse(Int, match(r"\d{1,2}", fecha).match))
        output = DataFrame(votante = String[], voto = String[])
        idx = findlast(ln -> startswith(ln, "Certifico correcto"), lns)
        idx = isa(idx, Integer) ? idx - 1 : lastindex(lns)
        for ln in @view(lns[nextind(lns, findfirst(ln -> endswith(ln, "Voto"), lns)):idx])
            votante, voto = split(ln, r"\s{2,}")
            push!(output, (votante, voto))
        end
        output[!,:tipo] .= tipo
        output[!,:número] .= número
        output[!,:votación] .= votación
        output[!,:fecha] .= fecha
        output[!,:resultado] .= resultado
        output
    else
        DataFrame()
    end
    # node = innertable_elem[1]
    output
end

function update()
    website = URI(scheme = "https", host = "senado.pr.gov", path = "/Pages/VotacionMedidas.aspx")
    response = request("GET", website)
    @assert response.status == 200
    
    
    innertable = Selector("table > tbody > tr")
    innertable_elem = eachmatch(innertable, html.root)
    
    foreach(parse_vote, innertable_elem)
end

function compile_data()
    files = filter!(path -> endswith(path, ".csv"), readdir(joinpath("data", "senado"), join = true))
    output = DataFrame()
    for file in files
        append!(output, CSV.read(file, DataFrame))
    end
    output
end


medidas = sort!(unique(string.(output[!,:tipo], lpad.(output[!,:número], 4, '0'))))
medidas = sort!(unique(string.(output[!,:tipo], " ", output[!,:número])))
query = string("fragment Source on BillNode{identifier sources{url}} ",
               "query Bills(",
               join(("\$_$i:String!" for i in eachindex(medidas)), ','),
               "){",
               join(("""_$i:bill(jurisdiction:"Puerto Rico",session:"2021-2024",identifier:\$_$i){...Source}"""
                     for i in eachindex(medidas)), ""),
               "}");
result = CLIENT.Query(query, operationName = "Bills", vars = Dict(zip(string.("_", eachindex(medidas)), medidas)))

data = JSON3.read(result.Data).data
only(data[:_1].sources).url
sources = DataFrame(tipo = String[], número = Int[], rid = Int[])
for node in values(data)
    tipo, número = split(node.identifier)
    rid = parse(Int, match(r"\d+$", only(node.sources).url).match)
    push!(sources, (tipo, parse(Int, número), rid))
end

output_wrid = join(output, sources, on = [:tipo, :número])

CSV.write(joinpath("data", "senado_sources.csv"), sources)
sources = CSV.read(joinpath("data", "senado_sources.csv"), DataFrame)

function buscar_comisión(rid)
    # rid = 136704
    url = URI(scheme = "https", host = "sutra.oslpr.org", path = "/osl/esutra/MedidaReg.aspx", query = ["rid" => rid])
    response = request("GET", url)
    html = parsehtml(String(response.body))
    write("tmp.html", string(html))
    eventos = eachmatch(Selector(".DataGridItemSyle > td > div > div > .col-12 > div"), html.root)
    referido = findfirst(evento -> startswith(nodeText(evento), "Comisión(es):"), eventos)
    comisión = isa(referido, Integer) ?
        filter!(!isempty, [ strip(nodeText(elem)) for elem in eachmatch(Selector("div > .smalltxt"), eventos[referido + 1]) ]) :
        String[]
    DataFrame(rid = rid, comisión = comisión)
end

comisiones = DataFrame(rid = Int[], comisión = String[])
empty!(comisiones)
for rid in sources[!,:rid]
    println(rid)
    append!(comisiones, buscar_comisión(rid))
end

final_output = join(output_wrid, comisiones, on = :rid)
replace!(final_output[!,:votante], "Moran Trinidad, Nitza" => "Morán Trinidad, Nitza")
final_output[!,:cuerpo] .= "Senado"
senadores = sort!(unique(final_output[!,:votante]))
for s in senadores
    println(s)
end
senadores = CSV.read(joinpath("data", "senadores.csv"), DataFrame)

load!(senadores, conn, "insert into votaciones_senado.senadores values(\$1,\$2,\$3);")

medidas = unique(final_output[!,[:rid, :tipo, :número, :comisión]])
medidas[!,:cuatrenio] .= 2021
execute(conn, "truncate votaciones_senado.medidas;")
load!(sort!(medidas[!,[:rid, :cuatrenio, :tipo, :número, :comisión]]),
      conn,
      "insert into votaciones_senado.medidas values(\$1,\$2,\$3,\$4,\$5);")
load!(sort!(unique(final_output[!,[:rid, :fecha, :votación, :resultado]])),
      conn,
      "insert into votaciones_senado.resultados_votaciones values(\$1,\$2,\$3,\$4);")
load!(sort!(unique(final_output[!,[:rid, :fecha, :votación, :votante, :voto]])),
      conn,
      "insert into votaciones_senado.votaciones values(\$1,\$2,\$3,\$4,\$5);")
# capabilities = Capabilities("chrome")
# wd = RemoteWebDriver(
#     capabilities,
#     host = ENV["WEBDRIVER_HOST"],
#     port = parse(Int, ENV["WEBDRIVER_PORT"]),
#     )
# # New Session
# rid = sources[1,:rid]
# session = Session(wd)
# url = URI(scheme = "https", host = "sutra.oslpr.org", path = "/osl/esutra/MedidaReg.aspx", query = ["rid" => rid])
# navigate!(session, string(url))
# ss = write("img.png", base64decode(screenshot(session)))
# título = element_text(Element(session, "css selector", "#ctl00_CPHBody_txtTitulo"))
# html = parsehtml(source(session))



eventos = eachmatch(Selector(".DataGridItemSyle > td > div > div > .col-12 > div"), html.root)
nodeText(eventos[1])
nodeText(eventos[2])

eventos[5]

medidas = DataFrame(execute(conn, "select * from votaciones_senado.medidas;"))
senadores = DataFrame(execute(conn, "select * from votaciones_senado.senadores;"))
votaciones = DataFrame(execute(conn, "select * from votaciones_senado.votaciones;"))
resultados_votaciones = DataFrame(execute(conn, "select * from votaciones_senado.resultados_votaciones;"))

CSV.write(joinpath("data", "medidas.csv"), medidas)
CSV.write(joinpath("data", "senadores.csv"), senadores)
CSV.write(joinpath("data", "votaciones.csv"), votaciones)
CSV.write(joinpath("data", "resultados_votaciones.csv"), resultados_votaciones)
