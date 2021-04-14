"""
    PRLeg :: Module

"""
module PRLeg

using HTTP: request, URI
using Cascadia: parsehtml, Selector, HTMLNode, HTMLText, nodeText, getattr
using Dates: Date
using PDFIO: pdDocOpen, pdDocGetInfo, pdDocGetPageCount, pdDocGetPage, pdPageExtractText, pdDocClose
using DataFrames: DataFrame
using CSV: CSV

const MESES = Dict(zip(["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
1:12))

function parse_vote(node::HTMLNode)
    votación = only(eachmatch(Selector("a"), node[1]))
    fecha = nodeText(votación)
    fecha = Date(parse(Int, match(r"\d{4}$", fecha).match),
                 MESES[match(r"(?<= de ).*(?= de )", fecha).match],
                 parse(Int, match(r"\d{1,2}", fecha).match))
    isfile(joinpath("data", "senado", "$fecha.csv")) && return
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
    for i in 2:npage
        page = pdDocGetPage(doc, i)
        text = pdPageExtractText(io, page)
        text = String(take!(io))
        lns = split(text, '\n')
        lns = split.(strip.(lns[findfirst(ln -> occursin(r"^\s+Votante\s+Voto", ln), lns) + 1:end]), r"\s{2,}")
        votante = first.(lns)
        voto = last.(lns)
        append!(data,
                DataFrame(cuerpo = "Senado", fecha = fecha, sesión = sesión, asamblea = asamblea, número = número, votante = votante, voto = voto))
    end
    close(io)
    CSV.write(joinpath("data", "senado", "$fecha.csv"), data)
end

function update()
    website = URI(scheme = "https", host = "senado.pr.gov", path = "/Pages/VotacionMedidas.aspx")
    response = request("GET", website)
    @assert response.status == 200
    html = parsehtml(String(response.body))
    
    innertable = Selector("table > tbody > tr")
    innertable_elem = eachmatch(innertable, html.root)
    
    foreach(parse_vote, innertable_elem)
end

end
