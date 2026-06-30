#!/usr/bin/env bash

set -euo pipefail

RECETAS_JSON="recetas.json"
HISTORIAL_JSON="historial_semanas.json"

dias=("Lunes" "Martes" "Miércoles" "Jueves" "Viernes")

########################################
# Proteína principal
########################################

proteina_principal() {
    local ingredientes="$1"

    if echo "$ingredientes" | grep -Eiq "pollo"; then
        echo "pollo"
    elif echo "$ingredientes" | grep -Eiq "pavo"; then
        echo "pavo"
    elif echo "$ingredientes" | grep -Eiq "ternera"; then
        echo "ternera"
    elif echo "$ingredientes" | grep -Eiq "cerdo|solomillo"; then
        echo "cerdo"
    elif echo "$ingredientes" | grep -Eiq "merluza"; then
        echo "merluza"
    elif echo "$ingredientes" | grep -Eiq "bacalao"; then
        echo "bacalao"
    elif echo "$ingredientes" | grep -Eiq "salmón"; then
        echo "salmon"
    elif echo "$ingredientes" | grep -Eiq "atun|atún"; then
        echo "atun"
    elif echo "$ingredientes" | grep -Eiq "sardina"; then
        echo "sardina"
    elif echo "$ingredientes" | grep -Eiq "huevo"; then
        echo "huevo"
    elif echo "$ingredientes" | grep -Eiq "garbanzo|lenteja|alubia"; then
        echo "legumbre"
    else
        echo "otro"
    fi
}

########################################
# Hidrato principal
########################################

hidrato_principal() {
    local receta="$1"

    local arroz=0
    local pasta=0
    local patata=0
    local legumbre=0

    while IFS="|" read -r ingrediente cantidad; do
        ingrediente=$(echo "$ingrediente" | tr '[:upper:]' '[:lower:]')

        if [[ "$ingrediente" =~ arroz ]]; then
            arroz=$((arroz + cantidad))
        fi

        if [[ "$ingrediente" =~ pasta ]] ||
           [[ "$ingrediente" =~ espagueti ]] ||
           [[ "$ingrediente" =~ macarr ]] ||
           [[ "$ingrediente" =~ noodles ]] ||
           [[ "$ingrediente" =~ gnocchi ]]; then
            pasta=$((pasta + cantidad))
        fi

        if [[ "$ingrediente" =~ patata ]] ||
           [[ "$ingrediente" =~ boniato ]]; then
            patata=$((patata + cantidad))
        fi

        if [[ "$ingrediente" =~ lenteja ]] ||
           [[ "$ingrediente" =~ garbanzo ]] ||
           [[ "$ingrediente" =~ alubia ]]; then
            legumbre=$((legumbre + cantidad))
        fi

    done < <(echo "$receta" | jq -r '.ingredients[] | "\(.ingredient)|\(.amount)"')

    local max=$arroz
    local tipo="arroz"

    if (( pasta > max )); then
        max=$pasta
        tipo="pasta"
    fi

    if (( patata > max )); then
        max=$patata
        tipo="patata"
    fi

    if (( legumbre > max )); then
        tipo="legumbre"
    fi

    echo "$tipo"
}

########################################
# Recetas bloqueadas (última semana)
########################################

IDS_BLOQUEADOS="[]"

if [[ -f "$HISTORIAL_JSON" ]]; then
    IDS_BLOQUEADOS=$(
        jq '
            if (.semanas | length) > 0 then
                (.semanas[-1].comidas + .semanas[-1].cenas)
            else
                []
            end
        ' "$HISTORIAL_JSON"
    )
fi

########################################
# Recetas disponibles
########################################

RECETAS_DISPONIBLES=$(
    jq \
        --argjson bloqueados "$IDS_BLOQUEADOS" '
        map(
            select(
                .id as $id | ($bloqueados | index($id)) | not
            )
        )
    ' "$RECETAS_JSON"
)

########################################
# Pools
########################################

COMIDAS_ARROZ=()
COMIDAS_PASTA=()
COMIDAS_PATATA=()
COMIDAS_LEGUMBRE=()

CENAS_ARROZ=()
CENAS_PASTA=()
CENAS_PATATA=()
CENAS_LEGUMBRE=()

########################################
# Clasificar recetas en pools
########################################

while read -r RECETA; do
    meal=$(echo "$RECETA" | jq -r '.meal')
    hidrato=$(hidrato_principal "$RECETA")

    case "$meal-$hidrato" in
        comida-arroz)    COMIDAS_ARROZ+=("$RECETA") ;;
        comida-pasta)    COMIDAS_PASTA+=("$RECETA") ;;
        comida-patata)   COMIDAS_PATATA+=("$RECETA") ;;
        comida-legumbre) COMIDAS_LEGUMBRE+=("$RECETA") ;;
        cena-arroz)      CENAS_ARROZ+=("$RECETA") ;;
        cena-pasta)      CENAS_PASTA+=("$RECETA") ;;
        cena-patata)     CENAS_PATATA+=("$RECETA") ;;
        cena-legumbre)   CENAS_LEGUMBRE+=("$RECETA") ;;
    esac

done < <(echo "$RECETAS_DISPONIBLES" | jq -c '.[]')

########################################
# Distribución de comidas (aleatorizada)
# Distribución ideal: 2 legumbre, 1 arroz, 1 pasta, 1 patata
# Si un pool no tiene suficientes recetas, ese slot se reasigna
# al tipo con más recetas disponibles en ese momento.
########################################

COMIDAS_TIPOS=()

# Slots ideales con su cantidad requerida
declare -A slots_ideales=([legumbre]=2 [arroz]=1 [pasta]=1 [patata]=1)

# Contador de cuántos slots de cada tipo ya están asignados
declare -A slots_asignados=([legumbre]=0 [arroz]=0 [pasta]=0 [patata]=0)

# Capacidad real de cada pool (número de recetas disponibles)
declare -A pool_capacidad=(
    [arroz]=${#COMIDAS_ARROZ[@]}
    [pasta]=${#COMIDAS_PASTA[@]}
    [patata]=${#COMIDAS_PATATA[@]}
    [legumbre]=${#COMIDAS_LEGUMBRE[@]}
)

for slot in 1 2 3 4 5; do
    # Buscar el tipo ideal con slots pendientes y capacidad suficiente
    tipo_elegido=""
    for tipo in legumbre patata arroz pasta; do
        pendientes=$(( slots_ideales[$tipo] - slots_asignados[$tipo] ))
        (( pendientes <= 0 )) && continue
        (( pool_capacidad[$tipo] > slots_asignados[$tipo] )) || continue
        tipo_elegido="$tipo"
        break
    done

    # Si ningún tipo ideal tiene capacidad, usar el que más recetas tenga disponibles
    if [[ -z "$tipo_elegido" ]]; then
        mejor=0
        for tipo in arroz pasta patata legumbre; do
            disponibles=$(( pool_capacidad[$tipo] - slots_asignados[$tipo] ))
            if (( disponibles > mejor )); then
                mejor=$disponibles
                tipo_elegido="$tipo"
            fi
        done
    fi

    if [[ -z "$tipo_elegido" ]]; then
        echo "ERROR: No hay recetas de comida suficientes para generar el menú" >&2
        exit 1
    fi

    COMIDAS_TIPOS+=("$tipo_elegido")
    slots_asignados[$tipo_elegido]=$(( slots_asignados[$tipo_elegido] + 1 ))
done

mapfile -t COMIDAS_TIPOS < <(printf "%s\n" "${COMIDAS_TIPOS[@]}" | sort -R)

########################################
# Selección de comidas
########################################

COMIDAS_ELEGIDAS=()
COMIDAS_HIDRATOS=()
COMIDAS_PROTEINAS=()

for i in "${!dias[@]}"; do
    tipo="${COMIDAS_TIPOS[$i]}"

    case "$tipo" in
        arroz)    pool_ref="COMIDAS_ARROZ" ;;
        pasta)    pool_ref="COMIDAS_PASTA" ;;
        patata)   pool_ref="COMIDAS_PATATA" ;;
        legumbre) pool_ref="COMIDAS_LEGUMBRE" ;;
    esac

    # Copiar el pool para ordenarlo aleatoriamente
    eval "pool_copia=(\"\${${pool_ref}[@]}\")"

    if (( ${#pool_copia[@]} == 0 )); then
        echo "ERROR: No hay recetas disponibles en el pool de comidas '$tipo'" >&2
        exit 1
    fi

    # Elegir índice aleatorio
    idx=$(( RANDOM % ${#pool_copia[@]} ))
    elegida="${pool_copia[$idx]}"

    COMIDAS_ELEGIDAS+=("$elegida")
    COMIDAS_HIDRATOS+=("$tipo")

    ingredientes=$(echo "$elegida" | jq -r '.ingredients[].ingredient')
    COMIDAS_PROTEINAS+=("$(proteina_principal "$ingredientes")")

    # Eliminar del pool original buscando por id
    elegida_id=$(echo "$elegida" | jq -r '.id')
    eval "pool_actual=(\"\${${pool_ref}[@]}\")"
    nuevo_pool=()
    for receta in "${pool_actual[@]}"; do
        rid=$(echo "$receta" | jq -r '.id')
        [[ "$rid" != "$elegida_id" ]] && nuevo_pool+=("$receta")
    done
    eval "${pool_ref}=(\"\${nuevo_pool[@]+\${nuevo_pool[@]}}\")"
done

########################################
# Selección de cenas (una por una, con restricciones)
########################################

CENAS_ELEGIDAS=()
CENAS_HIDRATOS=()
ULTIMA_CENA_HIDRATO=""

for i in "${!dias[@]}"; do
    comida_hidrato="${COMIDAS_HIDRATOS[$i]}"
    comida_proteina="${COMIDAS_PROTEINAS[$i]}"

    # Tipos de hidrato permitidos para la cena
    TIPOS_PERMITIDOS=()
    for tipo in arroz pasta patata legumbre; do
        [[ "$tipo" == "$comida_hidrato" ]] && continue
        [[ "$tipo" == "$ULTIMA_CENA_HIDRATO" ]] && continue
        TIPOS_PERMITIDOS+=("$tipo")
    done

    # Construir lista de candidatas válidas
    CANDIDATAS=()
    for tipo in "${TIPOS_PERMITIDOS[@]}"; do
        case "$tipo" in
            arroz)    eval "candidatas_tipo=(\"\${CENAS_ARROZ[@]+\${CENAS_ARROZ[@]}}\")" ;;
            pasta)    eval "candidatas_tipo=(\"\${CENAS_PASTA[@]+\${CENAS_PASTA[@]}}\")" ;;
            patata)   eval "candidatas_tipo=(\"\${CENAS_PATATA[@]+\${CENAS_PATATA[@]}}\")" ;;
            legumbre) eval "candidatas_tipo=(\"\${CENAS_LEGUMBRE[@]+\${CENAS_LEGUMBRE[@]}}\")" ;;
        esac
        CANDIDATAS+=("${candidatas_tipo[@]+"${candidatas_tipo[@]}"}")
    done

    # Filtrar por proteína y por no haber sido usada
    CANDIDATAS_VALIDAS=()
    for candidata in "${CANDIDATAS[@]}"; do
        [[ -z "$candidata" ]] && continue

        cid=$(echo "$candidata" | jq -r '.id')

        # ¿Ya usada esta semana?
        usada=0
        for r in "${COMIDAS_ELEGIDAS[@]}"; do
            [[ "$cid" == "$(echo "$r" | jq -r '.id')" ]] && usada=1 && break
        done
        (( usada )) && continue

        for r in "${CENAS_ELEGIDAS[@]}"; do
            [[ "$cid" == "$(echo "$r" | jq -r '.id')" ]] && usada=1 && break
        done
        (( usada )) && continue

        # ¿Misma proteína que la comida del día?
        ingredientes_c=$(echo "$candidata" | jq -r '.ingredients[].ingredient')
        proteina_c=$(proteina_principal "$ingredientes_c")
        [[ "$proteina_c" == "$comida_proteina" ]] && continue

        CANDIDATAS_VALIDAS+=("$candidata")
    done

    if (( ${#CANDIDATAS_VALIDAS[@]} == 0 )); then
        echo "ERROR: No hay cenas válidas para el ${dias[$i]}" >&2
        exit 1
    fi

    # Elegir aleatoriamente entre las válidas
    idx=$(( RANDOM % ${#CANDIDATAS_VALIDAS[@]} ))
    cena_elegida="${CANDIDATAS_VALIDAS[$idx]}"

    CENAS_ELEGIDAS+=("$cena_elegida")

    cena_hidrato=$(hidrato_principal "$cena_elegida")
    CENAS_HIDRATOS+=("$cena_hidrato")
    ULTIMA_CENA_HIDRATO="$cena_hidrato"

    # Eliminar del pool de cenas correspondiente
    cena_id=$(echo "$cena_elegida" | jq -r '.id')
    case "$cena_hidrato" in
        arroz)    pool_ref="CENAS_ARROZ" ;;
        pasta)    pool_ref="CENAS_PASTA" ;;
        patata)   pool_ref="CENAS_PATATA" ;;
        legumbre) pool_ref="CENAS_LEGUMBRE" ;;
    esac
    eval "pool_actual=(\"\${${pool_ref}[@]+\${${pool_ref}[@]}}\")"
    nuevo_pool=()
    for receta in "${pool_actual[@]+"${pool_actual[@]}"}"; do
        rid=$(echo "$receta" | jq -r '.id')
        [[ "$rid" != "$cena_id" ]] && nuevo_pool+=("$receta")
    done
    eval "${pool_ref}=(\"\${nuevo_pool[@]+\${nuevo_pool[@]}}\")"
done

########################################
# Imprimir menú
########################################

for i in "${!dias[@]}"; do
    echo "${dias[$i]}"
    echo

    comida="${COMIDAS_ELEGIDAS[$i]}"
    comida_nombre=$(echo "$comida" | jq -r '.receipt')

    echo "🍽️ Comida: $comida_nombre"
    echo "$comida" | jq -r '.ingredients[] | "   - \(.ingredient): \(.amount) g"'
    echo

    cena="${CENAS_ELEGIDAS[$i]}"
    cena_nombre=$(echo "$cena" | jq -r '.receipt')

    echo "🌙 Cena: $cena_nombre"
    echo "$cena" | jq -r '.ingredients[] | "   - \(.ingredient): \(.amount) g"'
    echo
done

########################################
# IDs para el script Python
########################################

echo "###IDS_COMIDAS###"
for receta in "${COMIDAS_ELEGIDAS[@]}"; do
    echo "$receta" | jq -r '.id'
done

echo "###IDS_CENAS###"
for receta in "${CENAS_ELEGIDAS[@]}"; do
    echo "$receta" | jq -r '.id'
done