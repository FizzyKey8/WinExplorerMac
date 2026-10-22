# Win11ExplorerMac — Explorador de Archivos Estilo Windows 11 para macOS

Aplicación nativa para **macOS 14+ (Sonoma / Sequoia)** escrita en **Swift 5.9+ / SwiftUI y AppKit**, diseñada para replicar la apariencia visual (Fluent UI / Mica, carpetas amarillas características) y todas las funciones clave del **Explorador de Archivos de Windows 11**.

---

## Características Principales

1. **Sistema de Pestañas Estilo Windows 11 (`Win11TabBarView`)**
   - Pestañas integradas en la barra superior junto a los botones de ventana de macOS.
   - Crear pestaña (`Cmd + T`), cerrar (`Cmd + W`), duplicar pestaña, cerrar otras pestañas y arrastrar para reordenar.
   - Clic derecho sobre cualquier carpeta → **"Abrir en una pestaña nueva"**.

2. **Barra de Comandos (`Win11CommandBarView`)**
   - Botón **`+ Nuevo`** para crear Carpetas, Documentos de texto (`.txt`), Markdown (`.md`) y JSON (`.json`).
   - Botones de acción directa: **Cortar (`Cmd + X`)**, **Copiar (`Cmd + C`)**, **Pegar (`Cmd + V`)**, **Cambiar nombre (`F2`)**, **Compartir**, **Eliminar a la Papelera (`Cmd + Delete`)** y **Comprimir a ZIP**.
   - Menús desplegables de **Ordenar** (Nombre, Fecha de modificación, Tipo, Tamaño; Ascendente/Descendente) y **Ver** (Iconos muy grandes, grandes, medianos, Lista, Detalles, Mostrar archivos ocultos `.dotfiles`, Mostrar extensiones).
   - Interruptores para el **Panel de vista previa** y el **Panel de detalles**.

3. **Barra de Direcciones y Navegación (`Win11AddressBarView`)**
   - Botones **Atrás**, **Adelante**, **Historial reciente**, **Subir un nivel** y **Actualizar**.
   - **Breadcrumbs interactivos** (`Este equipo > Macintosh HD (C:) > Users > ...`) que al hacer clic en el espacio libre o pulsar `Cmd + L` se convierten en una barra de ruta editable (acepta rutas como `~/Desktop`, `/Applications`, `Inicio`, `Este equipo`).
   - **Buscador instantáneo** en la esquina superior derecha.

4. **Menú Contextual de Clic Derecho de Windows 11 (`Win11ContextMenuOverlay`)**
   - **Fila superior de iconos de acción rápida**: Cortar, Copiar, Pegar, Cambiar nombre, Compartir y Eliminar.
   - Opciones contextuales completas: *Abrir*, *Abrir en una pestaña nueva*, *Abrir con...*, *Anclar/Desanclar del Acceso rápido*, *Extraer todo...* (para `.zip`), *Comprimir en archivo ZIP*, *Copiar como ruta de acceso*, *Abrir en Terminal*, *Mostrar en Finder* y *Propiedades*.

5. **Vistas de Inicio (`Home`) y Este Equipo (`This PC`)**
   - **Inicio**: Tarjetas de **Acceso rápido** (con chincheta de anclado) y tabla de **Archivos recientes**.
   - **Este equipo**: Tarjetas de **Dispositivos y unidades** con barras de capacidad ocupada/disponible en GB (en azul o rojo si supera el 90%) y carpetas principales del usuario.

---

## Cómo Abrir y Ejecutar en tu Mac

### Opción 1: Abrir directamente en Xcode (Recomendado)
1. Copia la carpeta `ExploradorMac` a tu Mac.
2. Abre la Terminal en esa carpeta y ejecuta:
   ```bash
   xed .
   ```
   *(O abre Xcode → **File > Open...** y selecciona la carpeta `ExploradorMac` o el archivo `Package.swift`).*
3. Selecciona **My Mac** como destino y presiona **`Cmd + R`** para compilar y ejecutar.

### Opción 2: Generar la app `.app` desde Terminal
Ejecuta el script incluido para compilar en modo Release y empaquetar `Win11ExplorerMac.app`:
```bash
chmod +x build_mac_app.sh
./build_mac_app.sh
open "build/Win11ExplorerMac.app"
```

---

## Atajos de Teclado (Estilo Windows 11 adaptados a Mac)

| Acción | Atajo |
| :--- | :--- |
| Nueva pestaña | `Cmd + T` |
| Cerrar pestaña | `Cmd + W` |
| Cortar archivos (con icono atenuado al 50%) | `Cmd + X` |
| Copiar archivos | `Cmd + C` |
| Pegar archivos (copia o mueve según corresponda) | `Cmd + V` |
| Copiar como ruta de acceso | `Cmd + Shift + C` |
| Cambiar nombre en línea | `F2` |
| Nueva carpeta | `Cmd + Shift + N` |
| Eliminar a la Papelera | `Cmd + Delete` |
| Editar barra de direcciones | `Cmd + L` |
| Subir un nivel de carpeta | `Cmd + ↑` |
| Propiedades del archivo/carpeta | `Cmd + I` |
| Actualizar carpeta | `Cmd + R` |
