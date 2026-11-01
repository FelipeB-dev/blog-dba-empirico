/* ==========================================================================
   main.js — único script del sitio:
     1. El botón "modo noche".
     2. El componente <sitio-pie>: el footer compartido por todas las páginas.
   Se carga en el <head> (sin defer) para aplicar el tema antes de pintar
   la página y evitar el parpadeo blanco al entrar en modo oscuro.
   ========================================================================== */

/* --------------------------------------------------------------------------
   COMPONENTE <sitio-pie>
   HTML no tiene "include", así que el footer se define una sola vez aquí
   como un Custom Element. Cada página solo escribe <sitio-pie></sitio-pie>.
   Para cambiar el footer en todo el sitio, se edita únicamente este texto.
   (No se usa fetch() de un footer.html porque el navegador lo bloquea al
   abrir las páginas con doble clic, desde file://.)
   -------------------------------------------------------------------------- */
customElements.define("sitio-pie", class extends HTMLElement {
  connectedCallback() {
    this.innerHTML =
      '<footer class="sitio-pie">' +
        '<div class="contenedor">' +
          '<p>© 2026 Luis Felipe Baquero · Hecho con HTML y CSS.</p>' +
          '<p>Actividad 1 · Desarrollo de Aplicaciones en Red · UNIR</p>' +
        '</div>' +
      '</footer>';
  }
});

(function () {
  var raiz = document.documentElement;
  var CLAVE = "tema";

  // 1. Leer la preferencia guardada. try/catch porque en modo incógnito
  //    algunos navegadores bloquean localStorage.
  var guardado = null;
  try { guardado = localStorage.getItem(CLAVE); } catch (e) {}
  if (guardado === "dark" || guardado === "light") {
    raiz.setAttribute("data-theme", guardado);
  }

  // 2. Saber qué tema se está viendo ahora (guardado o el del sistema).
  function temaActual() {
    var t = raiz.getAttribute("data-theme");
    if (t) return t;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  // 3. Cuando la página termina de cargar, conectar el botón.
  document.addEventListener("DOMContentLoaded", function () {
    var boton = document.querySelector(".btn-tema");
    if (!boton) return;

    // El texto del botón dice a qué modo se va a cambiar
    function rotular() {
      boton.textContent = temaActual() === "dark" ? "modo día" : "modo noche";
    }
    rotular();

    boton.addEventListener("click", function () {
      var nuevo = temaActual() === "dark" ? "light" : "dark";
      raiz.setAttribute("data-theme", nuevo);
      try { localStorage.setItem(CLAVE, nuevo); } catch (e) {}
      rotular();
    });
  });
})();
