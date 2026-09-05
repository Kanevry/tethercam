/* SwiftPM verlangt, dass alle Quellen eines Targets unter dem Paketverzeichnis liegen.
 * `shared/usbmux.c` liegt daneben, nicht darunter. Statt Symlinks (deren Aufloesung
 * SwiftPM je nach Version unterschiedlich handhabt) zieht dieser Shim die Datei per
 * relativem #include herein — deterministisch und ohne Kopie. Der Wahrheitsort
 * bleibt shared/usbmux.c. */
#include "../../../shared/usbmux.c"
