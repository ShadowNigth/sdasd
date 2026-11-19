# Strike Port Destruction · Offline para Godot

Primera versión del porte de escritorio a **Godot 4.3+**. Podés jugar eliminación local CT contra T, demolición con C4 o deathmatch por equipos, con compañeros y rivales controlados por bots. El juego no usa cuentas, servidores, Photon ni descargas en tiempo de ejecución.

## Abrir y jugar

1. Importá `project.godot` en Godot 4.3 o posterior. Esperá a que termine la primera importación de los recursos.
2. Presioná **F6** con `main.tscn` abierto o **F5** para ejecutar el proyecto.
3. Elegí `$2000$` o `AWP Lego 2`, bando, dificultad y cantidad de jugadores por equipo. En eliminación y demolición ganás al llegar a ocho rondas. En demolición, T planta en A y CT puede desactivar manteniendo **E**. En deathmatch reaparecés tras caer; gana el primer equipo en llegar a 30 bajas o el que lidere al terminar cinco minutos.

| Control | Acción |
| --- | --- |
| WASD / ratón | Moverse / apuntar |
| Clic izquierdo / derecho | Disparar / alternar la mira en armas compatibles |
| Espacio / Ctrl / Shift | Saltar / agacharse / caminar |
| R / 1 / 2 / 3 | Recargar / arma principal / pistola / cuchillo |
| E | Mantener para plantar/desactivar en el sitio A |
| G / F / H | Lanzar granada explosiva / aturdidora / de humo |
| B / Tab / Esc | Comprar en preparación / consultar marcador / pausar |

La ronda empieza con una fase de compra. El arsenal incluye 32 armas de fuego con modelos y sonidos recuperados y estadísticas adaptadas para este port. Las granadas se compran por separado; las aturdidoras requieren línea de visión y el humo interrumpe la detección de los bots. En `$2000$` podés recoger armas y granadas en las posiciones del original. En `AWP Lego 2`, acercate a una escalera y usá W/S para subir o bajar. El dinero se gana con bajas y resultados de ronda; si sobrevivís conservás el equipo. Si te eliminan, la cámara pasa a un compañero hasta la ronda siguiente. En pausa podés ajustar sensibilidad y volumen.

Los bots son propios de esta versión: buscan por rutas de navegación, detectan enemigos por campo de visión con oclusión, reaccionan según dificultad, recuerdan posiciones vistas, se desplazan lateralmente y son capaces de buscar una interrupción de la línea de visión al recargar. No dependen de lógica multijugador de Unity.
Los bots usan el esqueleto original con locomoción y postura de arma procedurales. En primera persona los brazos y guantes provienen de los modelos originales, con la pose base recuperada de un clip de Unity y movimientos de equipar, caminar, disparar y recargar adaptados a Godot. Se incluyen destellos, trazas, impactos, casquillos con cuerpos rígidos, pasos y sonidos de rebote.

## Qué se porta y qué queda pendiente

| Incluido | Pendiente para paridad con el original |
| --- | --- |
| Geometría estática, texturas principales, colisiones y puntos de aparición de los dos mapas recuperados | Disparadores y objetos destructibles originales, iluminación y efectos equivalentes |
| 32 armas de fuego, cuchillo, C4, tres granadas, escaleras para el jugador y dos personajes con sus materiales y esqueletos originales; brazos y guantes CT/T | Variantes, animaciones originales completas y sonidos restantes |
| Menú local, eliminación, demolición y deathmatch por equipos, economía, HUD, mira, pausa y espectador | Otros modos, interfaz y opciones completas del original, controles táctiles y exportación Android |

Esto **no es todavía un porte completo**. La referencia es una extracción de Unity con código descompilado y recursos serializados; se reutiliza contenido convertido y se reimplementa la lógica en GDScript. Las funciones de red, servicios y actualizador no son parte del objetivo offline.

## Procedencia y regeneración

Los recursos recuperados provienen del [repositorio SPD](https://github.com/ShadowNigth/spd/tree/43524877985da87fa2a9e7f99b37defe73c77358/decompiled), revisión `43524877985da87fa2a9e7f99b37defe73c77358`. No se incluyen las DLL, el APK ni las copias duplicadas de sus recursos. No se encontró una licencia de redistribución en la referencia: verificá los derechos de mapas, sonidos y modelos antes de publicar binarios o reutilizarlos fuera de este proyecto.

Los archivos generados ya están incluidos; sólo hace falta el siguiente procedimiento para regenerarlos:

```sh
python -m venv .venv
. .venv/bin/activate
pip install numpy PyYAML
python tools/convert_spd.py /ruta/a/spd/decompiled
python tools/rig_spd.py /ruta/a/spd/decompiled
```

## Verificación y exportación

```sh
python3 tests/check_assets.py
# Requiere el ejecutable de Godot 4.3 o posterior:
godot --headless --editor --path . --import
godot --headless --path . --script tests/smoke.gd
```

El test de Godot abre los dos mapas y comprueba navegación, economía y transiciones de ronda. El flujo de GitHub Actions ejecuta el escenario de prueba en Godot 4.3 y, si pasa, publica ejecutables de Linux y Windows como artefactos de la ejecución.

Para compilar, instalá las plantillas correspondientes a tu versión de Godot y usá **Proyecto → Exportar**. Se incluyen presets básicos para Linux y Windows; los ejecutables no se guardan en el árbol de Git.
