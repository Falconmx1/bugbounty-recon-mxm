import subprocess
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def run_recon(target):
    """
    Ejecuta el script de reconocimiento 'recon.sh' pasando el dominio en un archivo temporal.
    Asume que el script se llama 'bugbounty-recon-mxm' y está en el PATH.
    """
    script_name = "bugbounty-recon-mxm"  # El nombre con el que copiaste el script al PATH
    logger.info(f"Preparando ejecución de {script_name} para {target}")

    # Crear un directorio temporal para el archivo de targets y los resultados
    with tempfile.TemporaryDirectory() as temp_dir:
        logger.info(f"Usando directorio temporal: {temp_dir}")
        
        # Crear un archivo targets.txt con el dominio
        targets_file = os.path.join(temp_dir, "targets.txt")
        with open(targets_file, 'w') as f:
            f.write(target + "\n")
            logger.info(f"Archivo de objetivos creado: {targets_file}")
        
        # Ejecutar el script con el archivo de targets
        cmd = [script_name, targets_file]
        
        try:
            logger.info(f"Ejecutando comando: {' '.join(cmd)}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,  # 5 minutos
                check=False
            )
            
            output = result.stdout + "\n" + result.stderr
            if result.returncode != 0:
                logger.warning(f"El script terminó con código {result.returncode}. Output: {output[:500]}")
                raise RuntimeError(f"El script falló con código {result.returncode}. Revisa los logs.")
            
            logger.info(f"Reconocimiento completado. Tamaño del output: {len(output)} caracteres")
            return output
            
        except subprocess.TimeoutExpired:
            logger.error("El reconocimiento excedió el tiempo límite (5 minutos).")
            raise TimeoutError("El reconocimiento tomó demasiado tiempo.")
        except FileNotFoundError:
            logger.error(f"No se encontró el script '{script_name}'. Asegúrate de que esté instalado y en el PATH.")
            raise FileNotFoundError(f"Script '{script_name}' no encontrado.")
        except Exception as e:
            logger.error(f"Error inesperado ejecutando el reconocimiento: {e}")
            raise
