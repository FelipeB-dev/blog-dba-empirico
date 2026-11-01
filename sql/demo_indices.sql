-- =============================================================================
-- demo_indices.sql
-- Entrada 2: "Índices: cuando 'más' es peor"
--
-- Parte 1: la consulta de los consumos de UN cliente.
--   - Plan sin índice   -> TABLE ACCESS FULL (lee los 50.000 consumos)
--   - Se crea el índice
--   - Plan con índice   -> INDEX RANGE SCAN (lee solo 10 filas)
--
-- Parte 2: cuando el índice NO sirve.
--   Un índice sobre ESTADO no ayuda a buscar 'FACTURADO' (~90 % de las filas),
--   pero sí a buscar 'ERROR' (~0,05 %, unas 25 filas). El optimizador lo sabe gracias al
--   histograma que se pidió en setup_demo.sql.
--
-- EXPLAIN PLAN no ejecuta la consulta: solo guarda el plan en PLAN_TABLE.
-- DBMS_XPLAN.DISPLAY lo muestra en forma de tabla.
-- Requisito: haber corrido antes setup_demo.sql.
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200

-- Si el script ya se corrió, quitar los índices para empezar de cero
-- (ORA-01418 = el índice no existe)
BEGIN
  FOR i IN (SELECT 'IDX_CONSUMOS_CLIENTE' AS nombre FROM dual UNION ALL
            SELECT 'IDX_CONSUMOS_ESTADO' FROM dual)
  LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP INDEX ' || i.nombre;
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE != -1418 THEN RAISE; END IF;
    END;
  END LOOP;
END;
/

-- Limpiar planes viejos de esta demo
DELETE FROM plan_table WHERE statement_id LIKE 'demo_%';
COMMIT;


PROMPT
PROMPT ================================================================
PROMPT  PARTE 1. Consumos de un cliente
PROMPT ================================================================

PROMPT
PROMPT --- 1.1 Plan SIN índice  (pantallazo: plan-antes.png) ---

EXPLAIN PLAN SET STATEMENT_ID = 'demo_antes' FOR
  SELECT id_consumo, fecha_consumo, tipo, valor
    FROM consumos
   WHERE id_cliente = 1234;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'demo_antes', 'TYPICAL'));

-- Lo que se debe ver: TABLE ACCESS FULL sobre CONSUMOS.
-- Oracle recorre toda la tabla para quedarse con 10 filas.
-- (En FreeSQL me dio costo 102.)


PROMPT
PROMPT --- 1.2 Crear el índice sobre ID_CLIENTE ---

-- Además de acelerar la consulta, ID_CLIENTE es llave foránea:
-- indexarla evita bloqueos cuando se borran o actualizan clientes.
CREATE INDEX idx_consumos_cliente ON consumos (id_cliente);


PROMPT
PROMPT --- 1.3 Plan CON índice  (pantallazo: plan-despues.png) ---

EXPLAIN PLAN SET STATEMENT_ID = 'demo_despues' FOR
  SELECT id_consumo, fecha_consumo, tipo, valor
    FROM consumos
   WHERE id_cliente = 1234;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'demo_despues', 'TYPICAL'));

-- Lo que se debe ver: INDEX RANGE SCAN sobre IDX_CONSUMOS_CLIENTE
-- seguido de TABLE ACCESS BY INDEX ROWID BATCHED. El "Cost" baja mucho.
-- (En FreeSQL bajó de 102 a 11.)


PROMPT
PROMPT ================================================================
PROMPT  PARTE 2. Cuando el índice no sirve (opcional, para la entrada)
PROMPT ================================================================

CREATE INDEX idx_consumos_estado ON consumos (estado);

PROMPT
PROMPT --- 2.1 Buscar FACTURADO (~90 % de la tabla) ---

EXPLAIN PLAN SET STATEMENT_ID = 'demo_facturado' FOR
  SELECT * FROM consumos WHERE estado = 'FACTURADO';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'demo_facturado', 'BASIC ROWS'));

-- Se espera TABLE ACCESS FULL aunque el índice existe: saltar del índice
-- a la tabla 45.000 veces sale más caro que leerla de corrido.

PROMPT
PROMPT --- 2.2 Buscar ERROR (~0,05 % de la tabla) ---

EXPLAIN PLAN SET STATEMENT_ID = 'demo_error' FOR
  SELECT * FROM consumos WHERE estado = 'ERROR';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'demo_error', 'BASIC ROWS'));

-- Aquí sí se espera INDEX RANGE SCAN sobre IDX_CONSUMOS_ESTADO.
-- Mismo índice, distinto valor buscado, distinta decisión.

-- Limpieza opcional (quitar el comentario para dejar la tabla como estaba):
-- DROP INDEX idx_consumos_estado;
