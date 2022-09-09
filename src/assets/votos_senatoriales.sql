CREATE MATERIALIZED VIEW votaciones_senado.votos AS (
	with a as (
		select a.*, b.partido, b.distrito
		from votaciones_senado.votaciones a
		join votaciones_senado.senadores b
		on votante = senador
	),
    b as (
        select rid, tipo, número, ARRAY_AGG(comisión ORDER BY comisión) comisión
        from votaciones_senado.medidas b
        group by rid, tipo, número
    ),
	c as (
		select a.*, b.tipo, b.número, b.comisión
		from a
		join b
		on a.rid = b.rid
	),
	d as (
		select a.*, b.resultado
		from c a
		join votaciones_senado.resultados_votaciones b
		on a.rid = b.rid
		and a.fecha = b.fecha
		and a."númerodevotación" = b."númerodevotación"
	)
	select *
	from d
	order by rid, fecha, "númerodevotación", votante
);
