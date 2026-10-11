// Draws the service QR locally from the signed token (no external QR service), then wires Print.
(function () {
  var figure = document.getElementById("qr");
  var value = figure && figure.getAttribute("data-qr");
  if (figure && value && typeof qrcode === "function") {
    var qr = qrcode(0, "M");
    qr.addData(value, "Byte");
    qr.make();
    var count = qr.getModuleCount();
    var quiet = 4;
    var size = count + quiet * 2;
    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + size + " " + size);
    svg.setAttribute("shape-rendering", "crispEdges");
    svg.setAttribute("aria-hidden", "true");
    var bg = document.createElementNS(svgNS, "rect");
    bg.setAttribute("width", size); bg.setAttribute("height", size); bg.setAttribute("fill", "#FFFFFF");
    svg.appendChild(bg);
    var path = "";
    for (var r = 0; r < count; r++) {
      for (var c = 0; c < count; c++) {
        if (qr.isDark(r, c)) path += "M" + (c + quiet) + " " + (r + quiet) + "h1v1h-1z";
      }
    }
    var p = document.createElementNS(svgNS, "path");
    p.setAttribute("d", path); p.setAttribute("fill", "#000000");
    svg.appendChild(p);
    figure.appendChild(svg);
  }
  // The server fills in UTC timestamps; show them in the reader's own time.
  Array.prototype.forEach.call(document.querySelectorAll("time[data-local]"), function (el) {
    var when = new Date(el.getAttribute("datetime"));
    if (!isNaN(when)) el.textContent = when.toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  });
  var button = document.getElementById("print");
  if (button) button.addEventListener("click", function () { window.print(); });
})();
