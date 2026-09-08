#!/usr/bin/env python3
"""
audit-manual-debs.py
Escanea los paquetes instalados en el sistema e identifica aquellos que no
provienen de ningún repositorio APT configurado (instalados vía .deb manual o huérfanos),
indicando además si están soportados de forma nativa por deb-get.
"""

import sys
import subprocess

try:
    import apt
except ImportError:
    print("Error: El módulo python-apt no está instalado. Instálalo con: sudo apt install python3-apt")
    sys.exit(1)

def get_deb_get_supported():
    try:
        output = subprocess.check_output(['deb-get', 'list', '--raw'], stderr=subprocess.DEVNULL)
        return set(output.decode().split())
    except Exception:
        return set()

def main():
    cache = apt.Cache()
    deb_get_supported = get_deb_get_supported()
    
    manual_pkgs = []
    
    for pkg in cache:
        if pkg.is_installed:
            ver = pkg.installed
            origins = [o.origin for o in ver.origins if o.origin]
            if not origins:
                manual_pkgs.append({
                    'name': pkg.name,
                    'version': ver.version,
                    'summary': ver.summary,
                    'in_deb_get': pkg.name in deb_get_supported
                })
                
    manual_pkgs.sort(key=lambda x: x['name'])
    
    print(f"Total de paquetes instalados manualmente (.deb / sin repositorio): {len(manual_pkgs)}\n")
    print(f"{'PAQUETE':<30} {'VERSIÓN':<22} {'EN DEB-GET?':<12} {'DESCRIPCIÓN'}")
    print("=" * 95)
    
    for p in manual_pkgs:
        in_dg = "SÍ [deb-get]" if p['in_deb_get'] else "No"
        print(f"{p['name']:<30} {p['version']:<22} {in_dg:<12} {p['summary'][:40]}")

if __name__ == '__main__':
    main()
