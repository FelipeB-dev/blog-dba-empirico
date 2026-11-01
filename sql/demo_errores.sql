-- =============================================================================
-- demo_errores.sql
-- Entrada 3: "Errores de PL/SQL que todos cometemos (y yo también)"
--
-- 1. Tabla LOG_ERRORES.
-- 2. Procedimiento REGISTRAR_ERROR con PRAGMA AUTONOMOUS_TRANSACTION:
--    guarda el error en su propia transacción, así que el registro
--    sobrevive aunque el proceso que falló haga ROLLBACK.
-- 3. Procedimiento FACTURAR_CLIENTE que falla a propósito (periodo inválido)
--    después de haber modificado datos.
-- 4. Se ejecuta, falla, y se comprueba que:
--      - no quedó ningún consumo EN_PROCESO (hubo rollback)
--      - el error SÍ quedó en LOG_ERRORES
--
-- Requisito: haber corrido antes setup_demo.sql. Oracle 12c+ (columna IDENTITY).
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

PROMPT
PROMPT === 1. Tabla de log ===

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE log_errores PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;   -- -942: la tabla no existía
END;
/

CREATE TABLE log_errores (
  id_log     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha_error TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  usuario    VARCHAR2(128)  DEFAULT USER NOT NULL,
  modulo     VARCHAR2(100)  NOT NULL,   -- qué programa falló
  codigo     NUMBER,                    -- SQLCODE, p. ej. -1843
  mensaje    VARCHAR2(4000),            -- SQLERRM
  contexto   VARCHAR2(4000),            -- con qué datos estaba trabajando
  traza      VARCHAR2(4000)             -- en qué línea ocurrió (backtrace)
);


PROMPT
PROMPT === 2. Procedimiento de logging ===

CREATE OR REPLACE PROCEDURE registrar_error (
  p_modulo    IN VARCHAR2,
  p_codigo    IN NUMBER,
  p_mensaje   IN VARCHAR2,
  p_contexto  IN VARCHAR2 DEFAULT NULL
) IS
  -- Transacción autónoma: este COMMIT no confirma nada del proceso que
  -- llamó, y el ROLLBACK de ese proceso no borra este registro.
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO log_errores (modulo, codigo, mensaje, contexto, traza)
  VALUES (p_modulo,
          p_codigo,
          SUBSTR(p_mensaje, 1, 4000),
          SUBSTR(p_contexto, 1, 4000),
          -- Línea exacta donde se originó el error
          SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 4000));
  COMMIT;   -- obligatorio en una transacción autónoma
END registrar_error;
/
SHOW ERRORS


PROMPT
PROMPT === 3. Proceso de ejemplo que va a fallar ===

CREATE OR REPLACE PROCEDURE facturar_cliente (
  p_id_cliente IN NUMBER,
  p_periodo    IN VARCHAR2      -- formato AAAAMM
) IS
  v_inicio  DATE;
  v_filas   PLS_INTEGER;
BEGIN
  -- Paso 1: marcar EN_PROCESO los consumos pendientes del cliente
  UPDATE consumos
     SET estado = 'EN_PROCESO'
   WHERE id_cliente = p_id_cliente
     AND estado = 'PENDIENTE';
  v_filas := SQL%ROWCOUNT;

  -- Paso 2: convertir el periodo en fecha.
  -- Con '202613' (mes 13) esto lanza ORA-01843: mes no válido.
  v_inicio := TO_DATE(p_periodo, 'YYYYMM');

  -- Paso 3 (si todo sale bien): pasar de EN_PROCESO a FACTURADO
  UPDATE consumos
     SET estado = 'FACTURADO'
   WHERE id_cliente = p_id_cliente
     AND estado = 'EN_PROCESO';

  DBMS_OUTPUT.PUT_LINE(v_filas || ' consumos facturados desde ' || v_inicio);

EXCEPTION
  WHEN OTHERS THEN
    -- Se deja registro con el contexto (qué cliente, qué periodo)...
    registrar_error(
      p_modulo   => 'FACTURAR_CLIENTE',
      p_codigo   => SQLCODE,
      p_mensaje  => SQLERRM,
      p_contexto => 'id_cliente=' || p_id_cliente || ' periodo=' || p_periodo);
    -- ...y se vuelve a lanzar el error. Nada de tragárselo con NULL.
    RAISE;
END facturar_cliente;
/
SHOW ERRORS


PROMPT
PROMPT === 4. Prueba ===

PROMPT Consumos PENDIENTES del cliente 1234 ANTES:
SELECT COUNT(*) AS pendientes FROM consumos
 WHERE id_cliente = 1234 AND estado = 'PENDIENTE';

PROMPT
PROMPT Ejecutando facturar_cliente(1234, '202613')... (debe fallar con ORA-01843)

-- El error llega hasta aquí sin manejar: Oracle deshace lo que hizo el
-- bloque (el UPDATE), pero el registro autónomo ya quedó confirmado.
BEGIN
  facturar_cliente(1234, '202613');
END;
/

PROMPT
PROMPT Consumos EN_PROCESO DESPUÉS (debe dar 0: el UPDATE se deshizo):
SELECT COUNT(*) AS en_proceso FROM consumos
 WHERE estado = 'EN_PROCESO';

PROMPT
PROMPT === 5. Lo que quedó en el log  (pantallazo: log-errores.png) ===

COLUMN modulo   FORMAT A18
COLUMN mensaje  FORMAT A45
COLUMN contexto FORMAT A30
COLUMN traza    FORMAT A60

SELECT id_log,
       TO_CHAR(fecha_error, 'YYYY-MM-DD HH24:MI:SS') AS fecha_error,
       modulo, codigo, mensaje, contexto, traza
  FROM log_errores
 ORDER BY id_log;
