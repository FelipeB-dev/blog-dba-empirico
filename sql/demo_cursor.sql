-- =============================================================================
-- demo_cursor.sql
-- Entrada 1: "El cursor que tumbó un batch a las 3 a.m."
--
-- La misma carga hecha de dos maneras:
--   A) Cursor explícito, fila a fila: un FETCH y un INSERT por cada consumo.
--   B) BULK COLLECT ... LIMIT + FORALL: lotes de 1.000 filas.
--
-- La carga: copiar los 50.000 consumos a CONSUMOS_CARGA calculando el
-- valor con un impuesto del 19 %. Es la misma lógica en los dos casos;
-- lo único que cambia es cómo viajan las filas entre PL/SQL y SQL.
--
-- Requisito: haber corrido antes setup_demo.sql.
-- SET TIMING ON muestra "Elapsed / Transcurrido" después de cada bloque.
-- =============================================================================

SET SERVEROUTPUT ON
SET TIMING OFF

PROMPT
PROMPT === Preparación: tabla destino vacía ===

-- Borrar la tabla destino si quedó de una corrida anterior (ORA-00942 = no existe)
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE consumos_carga PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE consumos_carga (
  id_consumo     NUMBER(12)    PRIMARY KEY,
  id_cliente     NUMBER(10)    NOT NULL,
  fecha_consumo  DATE          NOT NULL,
  tipo           VARCHAR2(10)  NOT NULL,
  valor          NUMBER(12,2)  NOT NULL,
  valor_total    NUMBER(12,2)  NOT NULL     -- valor + 19 % de impuesto
);

-- A partir de aquí se mide el tiempo de cada bloque
SET TIMING ON

PROMPT
PROMPT === A) Carga fila a fila con cursor explícito ===
PROMPT     (pantallazo: cursor-fila-a-fila.png)

DECLARE
  -- Cursor explícito sobre todos los consumos
  CURSOR c_consumos IS
    SELECT id_consumo, id_cliente, fecha_consumo, tipo, valor
      FROM consumos;

  r        c_consumos%ROWTYPE;    -- una sola fila en memoria
  v_filas  PLS_INTEGER := 0;
BEGIN
  OPEN c_consumos;
  LOOP
    FETCH c_consumos INTO r;      -- trae UNA fila (un viaje al motor SQL)
    EXIT WHEN c_consumos%NOTFOUND;

    INSERT INTO consumos_carga    -- inserta UNA fila (otro viaje)
      (id_consumo, id_cliente, fecha_consumo, tipo, valor, valor_total)
    VALUES
      (r.id_consumo, r.id_cliente, r.fecha_consumo, r.tipo, r.valor,
       ROUND(r.valor * 1.19, 2));

    v_filas := v_filas + 1;
  END LOOP;
  CLOSE c_consumos;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Fila a fila: ' || v_filas || ' filas cargadas.');
END;
/

-- Vaciar la tabla destino para que la segunda carga empiece igual
SET TIMING OFF
TRUNCATE TABLE consumos_carga;
SET TIMING ON

PROMPT
PROMPT === B) Carga por lotes con BULK COLLECT + FORALL ===
PROMPT     (pantallazo: cursor-bulk.png)

DECLARE
  CURSOR c_consumos IS
    SELECT id_consumo, id_cliente, fecha_consumo, tipo, valor
      FROM consumos;

  -- Colección: guarda un lote completo de filas en memoria
  TYPE t_consumos IS TABLE OF c_consumos%ROWTYPE;
  l_lote   t_consumos;

  c_tam_lote CONSTANT PLS_INTEGER := 1000;   -- LIMIT: tope de memoria por lote
  v_filas    PLS_INTEGER := 0;
BEGIN
  OPEN c_consumos;
  LOOP
    -- Trae hasta 1.000 filas en un solo viaje
    FETCH c_consumos BULK COLLECT INTO l_lote LIMIT c_tam_lote;
    EXIT WHEN l_lote.COUNT = 0;

    -- Envía el lote completo al motor SQL en un solo viaje
    FORALL i IN 1 .. l_lote.COUNT
      INSERT INTO consumos_carga
        (id_consumo, id_cliente, fecha_consumo, tipo, valor, valor_total)
      VALUES
        (l_lote(i).id_consumo, l_lote(i).id_cliente, l_lote(i).fecha_consumo,
         l_lote(i).tipo, l_lote(i).valor, ROUND(l_lote(i).valor * 1.19, 2));

    v_filas := v_filas + l_lote.COUNT;
  END LOOP;
  CLOSE c_consumos;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('BULK + FORALL: ' || v_filas || ' filas cargadas.');
END;
/

SET TIMING OFF

-- Comprobación: las dos cargas dejan exactamente lo mismo
PROMPT
PROMPT === Comprobación ===
SELECT COUNT(*) AS filas, SUM(valor_total) AS suma_valor_total
  FROM consumos_carga;

-- Nota: el EXIT WHEN va con l_lote.COUNT = 0 y no con %NOTFOUND.
-- Con LIMIT, %NOTFOUND se vuelve verdadero en el último lote incompleto
-- y, si se pregunta justo después del FETCH, esas filas se pierden.
