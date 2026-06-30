import asyncio
import json
import logging
import os
import re
import subprocess
from datetime import date
from pathlib import Path

from telegram import Bot
from telegram.request import HTTPXRequest
from telegram.constants import ParseMode

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

TOKEN = os.environ["TELEGRAM_TOKEN"]
CANAL_ID = int(os.environ["TELEGRAM_CHANNEL_ID"])

HISTORIAL_JSON = Path("historial_semanas.json")

DIAS = [
    "Lunes",
    "Martes",
    "Miércoles",
    "Jueves",
    "Viernes"
]

MARCADOR_COMIDAS = "###IDS_COMIDAS###"
MARCADOR_CENAS = "###IDS_CENAS###"


def generar_menu():
    resultado = subprocess.run(
        ["bash", "./randomComida.sh"],
        capture_output=True,
        text=True,
        check=True
    )

    return resultado.stdout


def parsear_salida(texto):
    """
    Separa la salida del Bash en:
    - mensaje: todo el texto anterior a ###IDS_COMIDAS### (esto es lo que se envía a Telegram)
    - comidas: lista de 5 UUID
    - cenas: lista de 5 UUID
    """

    if MARCADOR_COMIDAS not in texto:
        raise ValueError(f"No se encontró el marcador {MARCADOR_COMIDAS} en la salida del script")

    if MARCADOR_CENAS not in texto:
        raise ValueError(f"No se encontró el marcador {MARCADOR_CENAS} en la salida del script")

    mensaje, resto = texto.split(MARCADOR_COMIDAS, 1)
    bloque_comidas, bloque_cenas = resto.split(MARCADOR_CENAS, 1)

    comidas = [linea.strip() for linea in bloque_comidas.strip().splitlines() if linea.strip()]
    cenas = [linea.strip() for linea in bloque_cenas.strip().splitlines() if linea.strip()]

    return mensaje.strip(), comidas, cenas


def validar_ids(comidas, cenas):
    if len(comidas) != 5:
        raise ValueError(f"Se esperaban 5 IDs de comidas, se obtuvieron {len(comidas)}")

    if len(cenas) != 5:
        raise ValueError(f"Se esperaban 5 IDs de cenas, se obtuvieron {len(cenas)}")


def dividir_por_dias(texto):
    bloques = {}

    patron = r"(Lunes|Martes|Miércoles|Jueves|Viernes)\n(.*?)(?=\n(?:Lunes|Martes|Miércoles|Jueves|Viernes)\n|\Z)"

    for match in re.finditer(patron, texto, re.DOTALL):
        dia = match.group(1)
        contenido = match.group(2).strip()

        bloques[dia] = contenido

    return bloques


def convertir_a_markdown(dia, contenido):

    contenido = contenido.replace(
        "🍽️ Comida:",
        "*🍽️ Comida:*"
    )

    contenido = contenido.replace(
        "🌙 Cena:",
        "*🌙 Cena:*"
    )

    return f"""#️⃣ *{dia}*

{contenido}
"""


def cargar_historial():
    if HISTORIAL_JSON.exists():
        with open(HISTORIAL_JSON, "r", encoding="utf-8") as f:
            return json.load(f)

    return {"semanas": []}


def actualizar_historial(comidas, cenas):
    historial = cargar_historial()

    nueva_semana = {
        "fecha": date.today().isoformat(),
        "comidas": comidas,
        "cenas": cenas
    }

    historial["semanas"].append(nueva_semana)

    with open(HISTORIAL_JSON, "w", encoding="utf-8") as f:
        json.dump(historial, f, indent=2, ensure_ascii=False)

    logging.info("historial_semanas.json actualizado")


def commit_y_push():
    subprocess.run(
        ["git", "add", str(HISTORIAL_JSON)],
        check=True
    )

    resultado = subprocess.run(
        ["git", "commit", "-m", "Actualizar historial semanal"],
        capture_output=True,
        text=True
    )

    if resultado.returncode != 0:
        if "nothing to commit" in resultado.stdout.lower() or "nothing to commit" in resultado.stderr.lower():
            logging.info("No había cambios que commitear en historial_semanas.json")
            return
        raise subprocess.CalledProcessError(
            resultado.returncode, resultado.args, resultado.stdout, resultado.stderr
        )

    subprocess.run(
        ["git", "push"],
        check=True
    )

    logging.info("Commit y push realizados correctamente")


async def enviar_menu_telegram(mensaje):

    request = HTTPXRequest(
        connection_pool_size=8,
        read_timeout=60,
        write_timeout=60,
        connect_timeout=30,
        pool_timeout=30
    )

    bot = Bot(
        token=TOKEN,
        request=request
    )

    menu_por_dias = dividir_por_dias(mensaje)

    await bot.send_message(
        chat_id=CANAL_ID,
        text=(
            "📅 *MENÚ SEMANAL*\n\n"
            "Aquí tienes la planificación de comidas de esta semana."
        ),
        parse_mode=ParseMode.MARKDOWN
    )

    for dia in DIAS:

        if dia not in menu_por_dias:
            continue

        mensaje_dia = convertir_a_markdown(
            dia,
            menu_por_dias[dia]
        )

        await bot.send_message(
            chat_id=CANAL_ID,
            text=mensaje_dia,
            parse_mode=ParseMode.MARKDOWN
        )

    logging.info("Menú semanal enviado correctamente")


async def main():

    try:
        salida = generar_menu()
    except subprocess.CalledProcessError as e:
        logging.error("Error al ejecutar randomComida.sh: %s", e.stderr)
        return

    try:
        mensaje, comidas, cenas = parsear_salida(salida)
        validar_ids(comidas, cenas)
    except ValueError as e:
        logging.error("Error al parsear la salida del script: %s", e)
        return

    try:
        actualizar_historial(comidas, cenas)
        commit_y_push()
    except Exception as e:
        logging.error("Error al actualizar/commitear el historial: %s", e)
        return

    await enviar_menu_telegram(mensaje)


if __name__ == "__main__":
    asyncio.run(main())