using Diana: GraphQLClient, HTTP.URI
using JSON3: JSON3
const API_OPENSTATES_TOKEN = "a61278f6-8e85-4b98-a427-05aedd5564b3"

client = GraphQLClient(string(URI(scheme = "https", host = "openstates.org", path = "/graphql")),
                    #    auth = "bearer $API_OPENSTATES_TOKEN",
                       headers = Dict("X-API-KEY" => API_OPENSTATES_TOKEN))

query = String(read(joinpath("src", "assets", "c.graphql")))
vars = Dict{String,Any}()

result = client.Query(query, operationName = "Jurisdictions", vars = vars)
json = JSON3.read(result.Data)
results = json.data.jurisdictions.edges

n = [ result.node.name for result in results]

sort!(n)
findfirst(x -> startswith(x, "Puerto Rico"), n)
results[40].node.id
getproperty.(results, :name)

length(json.data.jurisdictions.edges)
