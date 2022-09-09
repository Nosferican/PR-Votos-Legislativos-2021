with a as (
	select a.rid, a.fecha, a."númerodevotación", a.comisión,
		   a.votante a, a.partido a_partido, a.distrito a_distrito, a.voto a_voto,
		   b.votante b, b.partido b_partido, b.distrito b_distrito, b.voto b_voto
	from votaciones_senado.votos a
	join votaciones_senado.votos b
	on a.rid = b.rid
	and a.fecha = b.fecha
	and a."númerodevotación" = b."númerodevotación"
	and a.votante < b.votante
	and a.voto <> 'Ausente'
	and b.voto <> 'Ausente'
),
b as (
	select comisión, a, a_partido, b, b_partido, a_voto = b_voto voto
	from a
),
c as (
	select unnest(comisión) comisión, a, a_partido, b, b_partido, voto
	from b
),
d as (
	select comisión, a, a_partido, b, b_partido, avg(case when voto then 1 else 0 end) concordancia
	from c
	group by comisión, a, b, a_partido, b_partido
),
e as (
	select *
	from d
	where a_partido = 'MVC'
	and a_partido <> b_partido
	order by concordancia desc, a
),
f as (
	select b, b_partido, round(100.0 * max(concordancia), 2) concordancia, comisión
	from e
	group by comisión, b, b_partido
	order by comisión, concordancia desc, b
),
g as (
	select b_partido, round(100.0 * avg(concordancia), 2) concordancia, comisión
	from e
	group by comisión, b_partido
	order by comisión, concordancia desc
),
h as (
	select distinct on (comisión) comisión, b_partido, concordancia
	from g
	order by comisión, concordancia desc
)
select replace("comisión", 'Comisión de ', '') comisión, b_partido, concordancia
from h
order by concordancia asc
;
