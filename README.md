# Strike Port Destruction · Offline para Godot

Primera versión del porte de escritorio a **Godot 4.3+**. Podés jugar una partida local de eliminación CT contra T, con compañeros y rivales controlados por bots. El juego no usa cuentas, servidores, Photon ni descargas en tiempo de ejecución.

## Abrir y jugar

1. Importá `project.godot` en Godot 4.3 o posterior. Esperá a que termine la primera importación de los recursos.
2. Presioná **F6** con `main.tscn` abierto o **F5** para ejecutar el proyecto.
3. Elegí `$2000$` o `AWP Lego 2`, bando, dificultad y cantidad de jugadores por equipo. Ganás la partida al llegar a ocho rondas.

| Control | Acción |
| --- | --- |
| WASD / ratón | Moverse / apuntar |
| Clic izquierdo / derecho | Disparar / alternar la mira de la AWP |
| Espacio / Ctrl / Shift | Saltar / agacharse / caminar |
| R / 1 / 2 | Recargar / arma principal / pistola |
| B / Tab / Esc | Comprar en preparación / consultar marcador / pausar |

La ronda empieza con una fase de compra. El dinero se gana con bajas y resultados de ronda; si sobrevivís conservás el equipo. Si te eliminan, la cámara pasa a un compañero hasta la ronda siguiente. En pausa podés ajustar sensibilidad y volumen.

Los bots son propios de esta versión: buscan por rutas de navegación, detectan enemigos por campo de visión con oclusión, reaccionan según dificultad, recuerdan posiciones vistas, se desplazan lateralmente y son capaces de buscar una interrupción de la línea de visión al recargar. No dependen de lógica multijugador de Unity.

## Qué se porta y qué queda pendiente

| Incluido | Pendiente para paridad con el original |
| --- | --- |
| Geometría estática, texturas principales, colisiones y puntos de aparición de los dos mapas recuperados | Escaleras funcionales, disparadores y objetos destructibles originales, iluminación y efectos equivalentes |
| Modelos y disparos de Deagle, AK-47 y AWP; dos modelos de personajes con colores de equipo | Arsenal, granadas, variantes, esqueletos, animaciones originales y sonidos restantes |
| Menú local, eliminación por rondas, economía básica, HUD, mira, pausa y espectador | Otros modos, interfaz y opciones completas del original, controles táctiles y exportación Android |

Esto **no es todavía un porte completo**. La referencia es una extracción de Unity con código descompilado y recursos serializados; se reutiliza contenido convertido y se reimplementa la lógica en GDScript. Las funciones de red, servicios y actualizador no son parte del objetivo offline.

## Procedencia y regeneración

Los recursos recuperados provienen del [repositorio SPD](https://github.com/ShadowNigth/spd/tree/43524877985da87fa2a9e7f99b37defe73c77358/decompiled), revisión `43524877985da87fa2a9e7f99b37defe73c77358`. No se incluyen las DLL, el APK ni las copias duplicadas de sus recursos. No se encontró una licencia de redistribución en la referencia: verificá los derechos de mapas, sonidos y modelos antes de publicar binarios o reutilizarlos fuera de este proyecto.

Los archivos generados ya están incluidos; sólo hace falta el siguiente procedimiento para regenerarlos:

```sh
python -m venv .venv
. .venv/bin/activate
pip install numpy PyYAML
python tools/convert_spd.py /ruta/a/spd/decompiled
```

## Verificación y exportación

```sh
python3 tests/check_assets.py
# Requiere el ejecutable de Godot 4.3 o posterior:
godot --headless --editor --path . --import
godot --headless --path . --script tests/smoke.gd
```

El test de Godot abre los dos mapas y comprueba navegación, economía y transiciones de ronda. El entorno de trabajo verificó los activos y el análisis sintáctico de los scripts, pero no disponía de un binario de Godot para ejecutar la prueba de motor. El flujo de GitHub Actions deja esa comprobación automatizada cuando se suban los cambios.

Para compilar, instalá las plantillas correspondientes a tu versión de Godot y usá **Proyecto → Exportar**. Se incluyen presets básicos para Linux y Windows; no se incluyen ejecutables precompilados.
