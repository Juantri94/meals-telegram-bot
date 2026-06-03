import asyncio
import logging
import os

from telegram import Bot

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

TOKEN = os.environ["TELEGRAM_TOKEN"]
CANAL_ID = int(os.environ["TELEGRAM_CHANNEL_ID"])


async def enviar_mensaje():
    bot = Bot(token=TOKEN)

    mensaje = "👋 ¡Buen inicio de semana! Aquí tienes el reporte automático."

    await bot.send_message(
        chat_id=CANAL_ID,
        text=mensaje
    )

    logging.info("Mensaje enviado correctamente.")


if __name__ == "__main__":
    asyncio.run(enviar_mensaje())