#!/usr/bin/env bash

COMIDAS_JSON="recetas_comidas.json"
CENAS_JSON="recetas_cenas.json"

dias=("Lunes" "Martes" "Miércoles" "Jueves" "Viernes")

# =========================
# Funciones auxiliares
# =========================

obtener_proteina_principal() {

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

tipo_proteina() {

    case "$1" in
        pollo|pavo|ternera|cerdo)
            echo "carne"
            ;;
        merluza|bacalao|salmon|atun|sardina)
            echo "pescado"
            ;;
        huevo)
            echo "huevo"
            ;;
        legumbre)
            echo "legumbre"
            ;;
        *)
            echo "otro"
            ;;
    esac
}

tipo_hidrato() {

    local ingredientes="$1"

    if echo "$ingredientes" | grep -Eiq "arroz"; then
        echo "arroz"

    elif echo "$ingredientes" | grep -Eiq "pasta|espagueti|espaguetis|macarron|macarrones|gnocchi|noodles"; then
        echo "pasta"

    elif echo "$ingredientes" | grep -Eiq "patata|boniato"; then
        echo "patata"

    elif echo "$ingredientes" | grep -Eiq "garbanzo|lenteja|alubia"; then
        echo "legumbre"

    else
        echo "otro"
    fi
}

# =========================
# Seleccionar 5 comidas
# =========================

mapfile -t comidas_ids < <(
    jq -r 'to_entries[].key' "$COMIDAS_JSON" |
    awk 'BEGIN{srand()} {print rand() "\t" $0}' |
    sort -n |
    cut -f2- |
    head -5
)

cenas_usadas=""

# =========================
# Generar semana
# =========================

for i in "${!dias[@]}"; do

    comida_id="${comidas_ids[$i]}"

    comida=$(jq -r ".[$comida_id].receipt" "$COMIDAS_JSON")

    ingredientes_comida=$(
        jq -r \
        ".[$comida_id].ingredients[].ingredient" \
        "$COMIDAS_JSON"
    )

    proteina=$(obtener_proteina_principal "$ingredientes_comida")
    grupo_proteina=$(tipo_proteina "$proteina")
    hidrato=$(tipo_hidrato "$ingredientes_comida")

    mejor_cena=""

    while IFS=$'\t' read -r idx receta; do

        [[ -z "$idx" ]] && continue

        if echo "$cenas_usadas" | grep -Fxq "$idx"; then
            continue
        fi

        ingredientes_cena=$(
            jq -r \
            ".[$idx].ingredients[].ingredient" \
            "$CENAS_JSON"
        )

        proteina_cena=$(obtener_proteina_principal "$ingredientes_cena")
        grupo_cena=$(tipo_proteina "$proteina_cena")
        hidrato_cena=$(tipo_hidrato "$ingredientes_cena")

        # ------------------
        # Regla 1
        # No repetir proteína exacta
        # ------------------

        [[ "$proteina" == "$proteina_cena" ]] && continue

        # ------------------
        # Regla 2 y 3
        # Priorizar carne/pescado alternos
        # ------------------

        puntuacion=0

        if [[ "$grupo_proteina" == "carne" && "$grupo_cena" == "pescado" ]]; then
            puntuacion=$((puntuacion + 20))
        fi

        if [[ "$grupo_proteina" == "pescado" && "$grupo_cena" == "carne" ]]; then
            puntuacion=$((puntuacion + 20))
        fi

        # ------------------
        # Regla 4
        # Evitar arroz dos veces
        # ------------------

        if [[ "$hidrato" == "arroz" && "$hidrato_cena" == "arroz" ]]; then
            continue
        fi

        # ------------------
        # Regla 5
        # Evitar pasta dos veces
        # ------------------

        if [[ "$hidrato" == "pasta" && "$hidrato_cena" == "pasta" ]]; then
            continue
        fi

        # ------------------
        # Regla 6
        # Si comida lleva patata,
        # priorizar arroz/pasta/legumbre
        # ------------------

        if [[ "$hidrato" == "patata" ]]; then

            if [[ "$hidrato_cena" == "arroz" ]]; then
                puntuacion=$((puntuacion + 10))
            fi

            if [[ "$hidrato_cena" == "pasta" ]]; then
                puntuacion=$((puntuacion + 10))
            fi

            if [[ "$hidrato_cena" == "legumbre" ]]; then
                puntuacion=$((puntuacion + 10))
            fi
        fi

        puntuacion=$((puntuacion + RANDOM % 10))

        echo -e "${puntuacion}\t${idx}\t${receta}"

    done < <(
        jq -r 'to_entries[] | "\(.key)\t\(.value.receipt)"' "$CENAS_JSON"
    ) | sort -nr | head -1 > /tmp/cena_semana.txt

    mejor_cena=$(cut -f3 /tmp/cena_semana.txt)
    mejor_idx=$(cut -f2 /tmp/cena_semana.txt)

    cenas_usadas="${cenas_usadas}"$'\n'"${mejor_idx}"

    ingredientes_comida_formateados=$(
        jq -r "
            .[$comida_id].ingredients[]
            | \"   - \(.ingredient): \(.amount) g\"
        " "$COMIDAS_JSON"
    )

    ingredientes_cena_formateados=$(
        jq -r "
            .[$mejor_idx].ingredients[]
            | \"   - \(.ingredient): \(.amount) g\"
        " "$CENAS_JSON"
    )

    echo "${dias[$i]}"
    echo

    echo "🍽️ Comida: ${comida}"
    echo "$ingredientes_comida_formateados"
    echo

    echo "🌙 Cena: ${mejor_cena}"
    echo "$ingredientes_cena_formateados"
    echo

done

rm -f /tmp/cena_semana.txt