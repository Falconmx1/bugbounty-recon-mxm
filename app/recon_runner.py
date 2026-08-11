import subprocess
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def run_recon(target):
    """
    Ejecuta el script de reconocimiento 'recon.sh' pasando el dominio en un archivo temporal.
    """
    script_name = "bugbounty-recon-mxm"
    logger.info(f"Preparando ejecución de {script_name} para {target}")

    with tempfile.TemporaryDirectory() as temp_dir:
        logger.info(f"Usando directorio temporal: {temp_dir}")
        
        targets_file = os.path.join(temp_dir, "targets.txt")
        with open(targets_file, 'w') as f:
            f.write(target + "\n")
            logger.info(f"Archivo de objetivos creado: {targets_file}")
        
        # Cambiar al directorio del bot para que los resultados se guarden en ~/mxm-recon-bot/results/
        bot_dir = os.getcwd()
        cmd = [script_name, targets_file]
        
        try:
            logger.info(f"Ejecutando comando: {' '.join(cmd)}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
                cwd=bot_dir  # Ejecuta el script en el directorio del bot
            )
            
            output = result.stdout + "\n" + result.stderr
            if result.returncode != 0:
                logger.warning(f"El script terminó con código {result.returncode}. Output: {output[:500]}")
                raise RuntimeError(f"El script falló con código {result.returncode}. Revisa los logs.")
            
            # Buscar la carpeta de resultados generada
            results_dir = os.path.join(bot_dir, "results")
            if os.path.exists(results_dir):
                # Encontrar la carpeta más reciente
                target_dirs = [d for d in os.listdir(results_dir) if d.startswith(target)]
                if target_dirs:
                    latest_dir = sorted(target_dirs)[-1]
                    full_path = os.path.join(results_dir, latest_dir)
                    logger.info(f"Resultados encontrados en: {full_path}")
                    result_text = read_results(full_path)
                    output += f"\n\n### Resultados del reconocimiento:\n{result_text}"
                else:
                    output += "\n\nNo se encontraron carpetas de resultados para este dominio."
            else:
                output += "\n\nLa carpeta 'results/' no se creó."
            
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

def read_results(target_dir):
    """
    Lee los archivos de resultados generados por recon.sh y los devuelve como texto.
    """
    result_text = ""
    result_files = ["subdomains.txt", "http_probe.txt", "nmap_scan.txt", "nuclei_results.txt"]
    
    for file_name in result_files:
        file_path = os.path.join(target_dir, file_name)
        if os.path.exists(file_path):
            with open(file_path, 'r') as f:
                content = f.read()
                if content.strip():
                    # Limitar el tamaño del contenido para no sobrepasar el límite de comentarios de GitHub
                    if len(content) > 5000:
                        content = content[:5000] + "\n... (truncado por longitud)"
                    result_text += f"\n### 📄 {file_name}\n```\n{content}\n```\n"
                else:
                    result_text += f"\n### 📄 {file_name}\n*No se encontraron resultados.*\n"
        else:
            result_text += f"\n### 📄 {file_name}\n*Archivo no generado.*\n"
    
    return result_text
