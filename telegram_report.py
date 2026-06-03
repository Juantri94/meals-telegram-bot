import asyncio
import logging
import os
import re
import subprocess

from telegram import Bot
from telegram.constants import ParseMode

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

TOKEN = os.environ["TELEGRAM_TOKEN"]
CANAL_ID = int(os.environ["TELEGRAM_CHANNEL_ID"])

DIAS = [
    "Lunes",
    "Martes",
    "Miércoles",
    "Jueves",
    "Viernes"
]


def generar_menu():
    resultado = subprocess.run(
        ["bash", "./randomComida.sh"],
        capture_output=True,
        text=True,
        check=True
    )

    return resultado.stdout


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


async def enviar_mensajes():

    bot = Bot(token=TOKEN)

    menu = generar_menu()

    menu_por_dias = dividir_por_dias(menu)

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

        mensaje = convertir_a_markdown(
            dia,
            menu_por_dias[dia]
        )

        await bot.send_message(
            chat_id=CANAL_ID,
            text=mensaje,
            parse_mode=ParseMode.MARKDOWN
        )

    logging.info("Menú semanal enviado correctamente")


if __name__ == "__main__":
    asyncio.run(enviar_mensajes())