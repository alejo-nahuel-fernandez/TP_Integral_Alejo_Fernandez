#!/bin/bash
clear

###############################
#
# Parametros:
#  - Lista Dominios y URL
#
#  Tareas:
#  - Se debera generar la estructura de directorio pedida con 1 solo comando con las tecnicas enseñadas en clases
#  - Generar los archivos de logs requeridos.
#
###############################
LISTA=$1

LOG_FILE="/var/log/status_url.log"

ANT_IFS=$IFS
IFS=$'\n'

#---- Dentro del bucle ----#
 # Obtener el código de estado HTTP
 # STATUS_CODE=$(curl -LI -o /dev/null -w '%{http_code}\n' -s "$URL") # Comentado porque URL no está definida aquí en el template

 # Fecha y hora actual en formato yyyymmdd_hhmmss
 # TIMESTAMP=$(date +"%Y%m%d_%H%M%S") # Comentado porque se usará dentro del bucle


 # Registrar en el archivo /var/log/status_url.log
 # echo "$TIMESTAMP - Code:$STATUS_CODE - URL:$URL" |sudo tee -a  "$LOG_FILE" # Comentado porque se usará dentro del bucle

IFS=$ANT_IFS
