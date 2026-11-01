-- =============================================================================
-- setup_demo.sql
-- Esquema ficticio para las demos del blog "Diario de un DBA empírico".
--
-- Crea tres tablas de una facturación inventada:
--   CLIENTES  (5.000 filas)
--   FACTURAS  (5.000 filas, una por cliente)
--   CONSUMOS  (50.000 filas, con campo ESTADO)
--
-- Todos los datos son generados: nombres como "Cliente 00001", valores
-- aleatorios. No hay nada real.
--
-- Probado en Oracle FreeSQL (freesql.com). Funciona en Oracle 12c o superior.
-- Ejecutar en SQL Developer con F5 (Run Script) o en SQL*Plus / SQLcl:
--   @setup_demo.sql
-- Se puede volver a correr: borra las tablas si ya existen.
-- =============================================================================

SET SERVEROUTPUT ON
SET TIMING OFF

PROMPT
PROMPT === 1. Limpieza: borrar tablas de una corrida anterior ===

-- Se borran en orden inverso a las llaves foráneas.
-- ORA-00942 = "la tabla no existe": si sale ese error, se ignora.
BEGIN
  FOR t IN (SELECT 'CONSUMOS_CARGA' AS nombre FROM dual UNION ALL
            SELECT 'CONSUMOS'  FROM dual UNION ALL
            SELECT 'FACTURAS'  FROM dual UNION ALL
            SELECT 'CLIENTES'  FROM dual)
  LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.nombre || ' CASCADE CONSTRAINTS PURGE';
      DBMS_OUTPUT.PUT_LINE('Borrada: ' || t.nombre);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;   -- solo se ignora "no existe"
    END;
  END LOOP;
END;
/

PROMPT
PROMPT === 2. Creación de tablas ===

-- CLIENTES: los dueños de las líneas.
CREATE TABLE clientes (
  id_cliente   NUMBER(10)     CONSTRAINT pk_clientes PRIMARY KEY,
  nombre       VARCHAR2(100)  NOT NULL,
  ciudad       VARCHAR2(50)   NOT NULL,
  tipo_plan    VARCHAR2(20)   NOT NULL,
  fecha_alta   DATE           NOT NULL
);

-- FACTURAS: una factura por cliente y periodo (AAAAMM).
CREATE TABLE facturas (
  id_factura     NUMBER(10)    CONSTRAINT pk_facturas PRIMARY KEY,
  id_cliente     NUMBER(10)    NOT NULL
                 CONSTRAINT fk_facturas_cliente REFERENCES clientes,
  periodo        VARCHAR2(6)   NOT NULL,
  fecha_emision  DATE          NOT NULL,
  total          NUMBER(14,2)  DEFAULT 0 NOT NULL,
  estado         VARCHAR2(15)  NOT NULL
                 CONSTRAINT ck_facturas_estado
                 CHECK (estado IN ('PENDIENTE', 'EMITIDA', 'ANULADA'))
);

-- CONSUMOS: cada uso de voz, datos o SMS.
-- ESTADO: PENDIENTE, EN_PROCESO (mientras se factura), FACTURADO o ERROR.
-- Ojo: a propósito NO se crea índice sobre ID_CLIENTE (eso es la demo 2).
CREATE TABLE consumos (
  id_consumo     NUMBER(12)    CONSTRAINT pk_consumos PRIMARY KEY,
  id_cliente     NUMBER(10)    NOT NULL
                 CONSTRAINT fk_consumos_cliente REFERENCES clientes,
  fecha_consumo  DATE          NOT NULL,
  tipo           VARCHAR2(10)  NOT NULL
                 CONSTRAINT ck_consumos_tipo CHECK (tipo IN ('VOZ', 'DATOS', 'SMS')),
  cantidad       NUMBER(12,2)  NOT NULL,
  valor          NUMBER(12,2)  NOT NULL,
  estado         VARCHAR2(12)  DEFAULT 'PENDIENTE' NOT NULL
                 CONSTRAINT ck_consumos_estado
                 CHECK (estado IN ('PENDIENTE', 'EN_PROCESO', 'FACTURADO', 'ERROR')),
  id_factura     NUMBER(10)
                 CONSTRAINT fk_consumos_factura REFERENCES facturas
);

PROMPT
PROMPT === 3. Datos de ejemplo ===

-- Bloque que llena las tres tablas.
-- CONNECT BY LEVEL <= N es un truco de Oracle para generar N filas desde DUAL.
DECLARE
  c_clientes  CONSTANT PLS_INTEGER := 5000;
  c_consumos  CONSTANT PLS_INTEGER := 50000;
BEGIN
  -- 3.1 Clientes ficticios
  INSERT INTO clientes (id_cliente, nombre, ciudad, tipo_plan, fecha_alta)
  SELECT LEVEL,
         'Cliente ' || LPAD(LEVEL, 5, '0'),
         CASE MOD(LEVEL, 5)
           WHEN 0 THEN 'Ciudad A' WHEN 1 THEN 'Ciudad B' WHEN 2 THEN 'Ciudad C'
           WHEN 3 THEN 'Ciudad D' ELSE 'Ciudad E'
         END,
         CASE MOD(LEVEL, 3) WHEN 0 THEN 'BASICO' WHEN 1 THEN 'PLUS' ELSE 'EMPRESA' END,
         DATE '2015-01-01' + MOD(LEVEL * 37, 4000)
    FROM dual
  CONNECT BY LEVEL <= c_clientes;

  -- 3.2 Una factura emitida por cliente para el periodo 2026-09
  --     (el total se calcula al final, a partir de los consumos)
  INSERT INTO facturas (id_factura, id_cliente, periodo, fecha_emision, estado)
  SELECT id_cliente, id_cliente, '202609', DATE '2026-10-01', 'EMITIDA'
    FROM clientes;

  -- 3.3 Cincuenta mil consumos (10 por cliente).
  --     El estado se reparte de forma fija (reproducible en cada corrida):
  --       ~0,05 % ERROR, ~9 % PENDIENTE y el resto FACTURADO.
  --     Se usan 1999 y 11 (primos) para que cada cliente tenga de todo un poco.
  INSERT INTO consumos
         (id_consumo, id_cliente, fecha_consumo, tipo, cantidad, valor, estado, id_factura)
  SELECT n,
         MOD(n - 1, c_clientes) + 1,
         DATE '2026-09-01' + MOD(n, 30),
         CASE MOD(n, 3) WHEN 0 THEN 'VOZ' WHEN 1 THEN 'DATOS' ELSE 'SMS' END,
         ROUND(DBMS_RANDOM.VALUE(1, 500), 2),
         ROUND(DBMS_RANDOM.VALUE(50, 5000), 2),
         estado,
         CASE WHEN estado = 'FACTURADO' THEN MOD(n - 1, c_clientes) + 1 END
    FROM (SELECT LEVEL AS n,
                 CASE
                   WHEN MOD(LEVEL, 1999) = 0 THEN 'ERROR'
                   WHEN MOD(LEVEL, 11)  = 0 THEN 'PENDIENTE'
                   ELSE 'FACTURADO'
                 END AS estado
            FROM dual
          CONNECT BY LEVEL <= c_consumos);

  COMMIT;

  -- 3.4 Total de cada factura = suma de sus consumos facturados
  UPDATE facturas f
     SET total = (SELECT NVL(SUM(c.valor), 0)
                    FROM consumos c
                   WHERE c.id_factura = f.id_factura);
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Datos cargados.');
END;
/

PROMPT
PROMPT === 4. Estadísticas para el optimizador ===

-- Sin estadísticas el optimizador adivina. Se pide además un histograma
-- sobre ESTADO, porque sus valores están muy desbalanceados (se usa en
-- la segunda parte de demo_indices.sql).
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTES');
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'FACTURAS');
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => USER,
    tabname    => 'CONSUMOS',
    method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS SIZE 254 ESTADO');
END;
/

PROMPT
PROMPT === 5. Verificación ===

SELECT 'CLIENTES' AS tabla, COUNT(*) AS filas FROM clientes
UNION ALL
SELECT 'FACTURAS', COUNT(*) FROM facturas
UNION ALL
SELECT 'CONSUMOS', COUNT(*) FROM consumos;

-- Reparto de estados en CONSUMOS
SELECT estado, COUNT(*) AS filas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 2) AS porcentaje
  FROM consumos
 GROUP BY estado
 ORDER BY filas DESC;
