with a as (
	SELECT votante, voto, partido, distrito
	FROM votaciones_senado.votos
),
b as (
	select votante, partido, distrito, voto, count(*)
	from a
	group by votante, partido, distrito, voto
),
c as (
	select *
	from b
	where voto = 'Ausente'
),
d as (
	select a.*, coalesce(count, 0) ausencias
	from votaciones_senado.senadores a
	left join c b
	on senador = votante
),
e as (
	select *
	from d
	order by ausencias desc
)
select *
from e;
