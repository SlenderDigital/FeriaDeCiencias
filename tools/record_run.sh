#!/bin/bash
# T9: prepara una corrida grabada del juego real (lo ejecuta el MCP).
# Uso: tools/record_run.sh "9=sweep,31=fan_a,..."
set -u
cd "$(dirname "$0")/.."
LIST="${1:-9=sweep,31=fan_a,38=fan_b,52=wave_a,58=wave_b,66=fan_c,72=corridor,80=fan_d,90=fan_e,99=rings}"
printf '%s' "$LIST" > /tmp/jsab_shot_list.txt
touch /tmp/jsab_autoplay.flag
rm -f /tmp/shot_*.png
echo "listo: lista='$LIST' flag=ok"
