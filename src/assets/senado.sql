CREATE TABLE IF NOT EXISTS votaciones_senado.medidas
(
    rid integer not null,
    cuatrenio smallint not null,
    tipo character varying(3) not null,
    "número" smallint not null,
    "comisión" text
);
CREATE TABLE IF NOT EXISTS votaciones_senado.senadores
(
    senador text,
    partido character varying(3) NOT NULL,
    distrito smallint NOT NULL
);
CREATE TABLE IF NOT EXISTS votaciones_senado.votaciones
(
    rid integer not null,
    fecha date not null,
    "númerodevotación" smallint not null,
    votante text not null,
    voto text not null,
    CONSTRAINT voto_en_medida UNIQUE (rid, fecha, "númerodevotación", votante)
);
CREATE TABLE IF NOT EXISTS votaciones_senado.resultados_votaciones
(
    rid integer not null,
    fecha date not null,
    "númerodevotación" smallint not null,
    resultado text not null,
    CONSTRAINT resultado_de_votaciones UNIQUE (rid, fecha, "númerodevotación", resultado)
);
