# WinExplorerMac — Explorador de Archivos Estilo Windows 11 para macOS

Aplicación nativa para **macOS 14+ (Sonoma / Sequoia)** escrita en **Swift 5.9+ / SwiftUI y AppKit**, diseñada para replicar con máxima fidelidad la apariencia visual (Fluent UI / Mica, carpetas amarillas características, barra de comandos y pestañas) y las funciones clave del **Explorador de Archivos de Windows 11**.

<div align="center">
  <img src="Resources/Captura%20de%20pantalla.png" alt="WinExplorerMac - Vista Principal" width="95%" style="border-radius: 10px; box-shadow: 0 8px 30px rgba(0,0,0,0.3);" />
</div>

---

## 🎨 Temas Visuales Integrados

WinExplorerMac cuenta con un selector de temas en la barra de menús (**Tema**):

| Windows 11 Clásico (Fluent) | Minimalista Oscuro (OLED) | Liquid Glass (Acrílico / Mica) |
| :---: | :---: | :---: |
| <img src="Resources/Captura%20de%20pantalla.png" alt="Tema Windows 11 Clásico" width="100%"/> | <img src="Resources/Captura%20de%20pantalla2.png" alt="Tema Minimalista Oscuro" width="100%"/> | <img src="Resources/Captura%20de%20pantalla3.png" alt="Tema Liquid Glass" width="100%"/> |
| Apariencia idéntica a Windows 11 con tonos grises Fluent UI. | Contraste puro y fondos oscuros profundos. | Efecto translúcido y desenfoque dinámico sobre tu fondo de pantalla. |

---

## Características Principales

### 1. Sistema de Pestañas Estilo Windows 11 (`Win11TabBarView`)
- Pestañas modernas integradas en la barra superior junto a los controles de ventana.
- Atajos nativos: Crear pestaña (`Cmd + T`), cerrar pestaña (`Cmd + W`), duplicar pestaña y cerrar otras pestañas.
- Clic derecho sobre cualquier carpeta → **"Abrir en una pestaña nueva"**.

### 2. Barra de Comandos Completa (`Win11CommandBarView`)
- Botón **`+ Nuevo`** para crear Carpetas, Documentos de texto (`.txt`), Markdown (`.md`) y JSON (`.json`).
- Botones de acción directa: **Cortar (`Cmd + X`)**, **Copiar (`Cmd + C`)**, **Pegar (`Cmd + V`)**, **Cambiar nombre (`F2`)**, **Compartir**, **Eliminar a la Papelera (`Cmd + Delete`)** y **Comprimir a ZIP**.
- Menús desplegables:
  - **Ordenar**: Por Nombre, Fecha de modificación, Tipo y Tamaño (Ascendente / Descendente).
  - **Ver**: Iconos muy grandes, grandes, medianos, lista compacta, detalles, extensiones de archivo y elementos ocultos (`.dotfiles`).
- Paneles laterales: Activación rápida del **Panel de vista previa** y del **Panel de detalles**.

### 3. Barra de Direcciones y Navegación Inteligente (`Win11AddressBarView`)
- Botones de historial: **Atrás**, **Adelante**, **Historial de carpetas**, **Subir un nivel** y **Actualizar**.
- **Breadcrumbs interactivos** (`Este equipo > Macintosh HD (C:) > Users > ...`) con clic para desplegar subdirectorios o pulsar `Cmd + L` para editar la ruta directamente.
- Buscador instantáneo integrado.

### 4. Integración en la Nube y Almacenamiento
- Detección automática de **iCloud Drive** y unidades en la nube (**Clarodrive**, OneDrive, etc.).
- **Despliegue en árbol con chevrons** en la barra lateral para explorar subcarpetas de la nube al instante.
- **Streaming directo y previsualización de alta velocidad**: Previews instantáneas de fotos y streaming multimedia sin necesidad de descargar gigabytes de archivos previamente.
- Indicador visual de descarga y liberación de espacio en disco local.

### 5. Vistas de Inicio (`Home`) y Este Equipo (`This PC`)
- **Inicio**: Tarjetas de **Acceso rápido** personalizables con chincheta de anclaje y sección de **Archivos recientes** (conmutables entre vista de **iconos grandes con miniaturas** o **tabla de detalles con fecha y ubicación**).
  - **Acciones completas de la barra de comandos**: Copiar, Cortar, Pegar, Renombrar, Eliminar a la papelera, Compartir y Comprimir directamente sobre elementos de Inicio.
  - **Apertura instantánea y miniaturas de la nube**: Detección de archivos en caché local para apertura inmediata (< 1 ms) sin re-descargas ni bloqueos, con generación de miniaturas e iconos en tiempo real.
  - **Selección múltiple por arrastre (Marquee)** en cualquier zona de la vista de Inicio.
- **Este equipo**: Unidades de disco y volúmenes montados con barras de estado de capacidad en GB (color azul, o rojo si supera el 90% de ocupación).

### 6. Renombrado In-Place Inteligente (`WinRenameTextField`)
- Activación inmediata con **`F2`** o el icono de renombrar de la barra de comandos, seleccionando automáticamente solo el nombre sin la extensión para edición directa.
- **Visualización completa de nombres largos**: El cuadro de edición se adapta para mostrar el nombre completo de forma legible sin requerir desplazamiento.
- **Tarjeta flotante Fluent**: Fondo oscuro opaco de alto contraste con borde azul de foco y elevación `.zIndex` con ocultamiento dinámico del texto vecino, evitando solapamientos o transparencias con elementos adyacentes en cuadrícula.

### 7. Selección Múltiple Avanzada
- **Selección rectangular (Marquee selection)** arrastrando con el ratón tanto en carpetas como en Inicio.
- **Deselección interactiva con `Shift` y `Cmd`**: Al hacer clic con la tecla `Shift` o `Cmd` presionada sobre elementos ya seleccionados, se alternan o deseleccionan con precisión.

### 8. Explorador Predeterminado del Sistema y Rendimiento
- Capacidad para establecerse como el **gestor de archivos predeterminado** de macOS desde el menú superior.
- Al descargar una imagen o archivo en navegadores como **Microsoft Edge** o Google Chrome y pulsar *"Mostrar en la carpeta"*, WinExplorerMac se abre automáticamente seleccionando el archivo.
- **Arranque asíncrono ultra-rápido**: Carga diferida en memoria para evitar llamadas bloqueantes al sistema de archivos virtual (VFS) de proveedores en la nube (iCloud, OneDrive, Clarodrive).

---

## Atajos de Teclado (Windows 11 en Mac)

| Acción | Atajo |
| :--- | :--- |
| Nueva pestaña | `Cmd + T` |
| Cerrar pestaña | `Cmd + W` |
| Cortar archivos (icono atenuado al 50%) | `Cmd + X` |
| Copiar archivos | `Cmd + C` |
| Pegar archivos | `Cmd + V` |
| Copiar como ruta de acceso | `Cmd + Shift + C` |
| Cambiar nombre en línea | `F2` |
| Nueva carpeta | `Cmd + Shift + N` |
| Eliminar a la Papelera | `Cmd + Delete` |
| Editar barra de direcciones | `Cmd + L` |
| Subir un nivel de carpeta | `Cmd + ↑` |
| Propiedades del archivo o carpeta | `Cmd + I` |
| Actualizar vista | `Cmd + R` |
| Selección / Deselección múltiple | `Cmd + Clic` / `Shift + Clic` |
| Selección por recuadro (Marquee) | Arrastrar con ratón |

---

## Instalación y Compilación

### Opción 1: Compilar el instalador (.dmg y .app) desde Terminal
```bash
chmod +x build_mac_app.sh
./build_mac_app.sh
```
Esto generará:
- `build/WinExplorerMac.app` (aplicación firmada lista para usar)
- `build/WinExplorerMac.dmg` (instalador arrastrable a la carpeta Aplicaciones)

### Opción 2: Abrir en Xcode
1. Abre Xcode y selecciona la carpeta del proyecto o ejecuta:
   ```bash
   xed .
   ```
2. Selecciona **My Mac** y pulsa **`Cmd + R`** para ejecutar.
