<p align="center">
  <img src="Images/LogoAppMacNTFS.png" alt="MacNTFS Logo" width="150">
</p>

<h1 align="center">MacNTFS</h1>

<p align="center">
  <strong>EN</strong> — Native macOS app for full NTFS read/write support on external drives.<br>
  <strong>ES</strong> — Aplicación nativa de macOS para lectura y escritura completa en discos externos NTFS.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/macOS%2026%20Tahoe-supported-brightgreen" alt="macOS 26 Tahoe">
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon-lightgrey" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## English

### The Problem

macOS detects NTFS-formatted drives (Windows) but mounts them as **read-only**. You can see your files but cannot modify, copy to, or delete anything. The alternatives are reformatting (losing all data) or buying expensive commercial software.

### The Solution

MacNTFS re-mounts NTFS drives with full write support using `ntfs-3g` and `FUSE-T`. One click — no reformatting, no data loss. The drive remains fully compatible with Windows.

**Confirmed working on macOS 26 Tahoe (arm64 Apple Silicon):** copy, paste, move, and delete files on NTFS drives.

### Features

| Feature | Description |
|---------|-------------|
| **Auto-detection** | Detects external drives instantly when connected via USB or hub |
| **NTFS identification** | Identifies filesystem type and highlights NTFS drives with visual status |
| **One-click R/W mount** | Re-mounts NTFS drives with full write support via ntfs-3g + FUSE-T |
| **Stable mount state** | Tolerant of macOS DiskArbitration cycling — mounted status persists in UI |
| **Native notifications** | macOS notifications when drives connect or disconnect |
| **Live logs** | Real-time operation log panel with copy-to-clipboard |
| **Dark mode** | Full support for System, Light, and Dark themes |
| **Bilingual** | English and Spanish interface with instant language switching |
| **Storage indicator** | Visual bar showing drive capacity at a glance |
| **Status bar** | Persistent bottom bar showing disk count, NTFS count, and mount status |

### How It Works

```
Connect NTFS drive via USB
        │
        ▼
MacNTFS detects drive automatically (DiskArbitration API)
        │
        ▼
Click "Mount with Write Support"
        │
        ▼
App unmounts read-only NTFS mount → re-mounts via ntfs-3g + FUSE-T (NFS loopback)
        │
        ▼
Full access — copy, move, rename, delete
        │
        ▼
Eject safely → drive works on Windows exactly the same
```

### Why FUSE-T instead of macFUSE

macFUSE requires a kernel extension (kext) that **cannot load on macOS 26 Tahoe on Apple Silicon** due to System Integrity Protection and the new FSKit architecture. FUSE-T uses an NFS loopback mechanism instead of a kext — no kernel extension required, no SIP bypass needed.

---

### Installation (Full Setup Guide)

This is a developer/power-user tool. Full setup requires Terminal. Follow each step exactly.

#### Step 1 — Install Homebrew (if not installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the "Next steps" shown in the terminal to add Homebrew to your PATH.

#### Step 2 — Install FUSE-T

Download and install from the official website: **https://www.fuse-t.org/**

Or via Homebrew cask:

```bash
brew install --cask fuse-t
```

Verify installation:

```bash
ls /Library/Frameworks/fuse_t.framework && echo "FUSE-T OK"
```

#### Step 3 — Build ntfs-3g from source

ntfs-3g must be compiled from source and patched to link against `fuse_t.framework` instead of the default `libfuse`. The standard `brew install ntfs-3g` binary links to macFUSE and will not work.

```bash
# Install build dependencies
brew install autoconf automake libtool pkg-config

# Clone ntfs-3g source
git clone https://github.com/tuxera/ntfs-3g.git
cd ntfs-3g

# Configure and compile against fuse_t.framework
./autogen.sh
./configure \
  CFLAGS="-I/Library/Frameworks/fuse_t.framework/Headers" \
  LDFLAGS="-F/Library/Frameworks -framework fuse_t" \
  --disable-ntfsprogs \
  --disable-crypto
make -j$(sysctl -n hw.logicalcpu)
sudo make install
```

Patch the installed binary to use the correct library path:

```bash
sudo install_name_tool -change \
  /usr/local/lib/libfuse.2.dylib \
  /Library/Frameworks/fuse_t.framework/fuse_t \
  /opt/homebrew/bin/ntfs-3g
```

Verify:

```bash
otool -L /opt/homebrew/bin/ntfs-3g | grep fuse
# Should show: /Library/Frameworks/fuse_t.framework/fuse_t
```

Test mount (replace `diskXsY` with your actual disk identifier from `diskutil list`):

```bash
sudo diskutil unmount force /dev/diskXsY
sudo mkdir -p /Volumes/NTFSTEST
sudo /opt/homebrew/bin/ntfs-3g /dev/diskXsY /Volumes/NTFSTEST \
  -o local,allow_other,auto_xattr,big_writes,noatime,remove_hiberfile
mount | grep NTFSTEST   # Should show: fuse-t:/... (nfs)
echo "write test" > /Volumes/NTFSTEST/test.txt && echo "WRITE OK"
```

#### Step 4 — Configure sudo privileges (NOPASSWD)

The app calls `sudo` via `Process()` — no password dialog appears, no terminal required. This requires NOPASSWD entries for the specific binaries used.

```bash
sudo tee /etc/sudoers.d/ntfs3g << 'EOF'
ALL ALL=(ALL) NOPASSWD: /usr/bin/pkill
ALL ALL=(ALL) NOPASSWD: /usr/sbin/diskutil
ALL ALL=(ALL) NOPASSWD: /bin/mkdir
ALL ALL=(ALL) NOPASSWD: /opt/homebrew/bin/ntfs-3g
ALL ALL=(ALL) NOPASSWD: /sbin/umount
EOF
sudo chmod 440 /etc/sudoers.d/ntfs3g
sudo visudo -c && echo "sudoers OK"
```

> **Security note:** These entries allow any admin user on this Mac to run those five specific binaries as root without a password. They are scoped to exact paths — no wildcard commands.

#### Step 5 — Grant Full Disk Access to MacNTFS

macOS requires explicit Full Disk Access permission for apps that access raw disk devices (`/dev/diskXsY`).

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to and select **MacNTFS.app**
4. Toggle it **ON**
5. Restart MacNTFS if it was already open

Without this, ntfs-3g will fail with `Operation not permitted` when trying to read the NTFS partition.

#### Step 6 — Build and run the app

**From source:**

```bash
git clone https://github.com/JhojanAlexanderCalambasRamirez/MacNTFS.git
cd MacNTFS
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS -configuration Release build
```

The built app will be at `build/Release/MacNTFS.app` (or wherever your derived data points).

**Or open in Xcode:**

```bash
open MacNTFS.xcodeproj
```

Then build with `⌘B` and run with `⌘R`.

---

### First Launch — macOS Gatekeeper

Since the app is not signed with an Apple Developer certificate, macOS will block it on first launch. This is normal and safe.

1. Go to **Applications** folder in Finder
2. **Right-click** (Control+click) on **MacNTFS.app** — do NOT double-click
3. Click **Open** from the context menu
4. A dialog will appear: "macOS cannot verify the developer" → Click **Open**
5. Done. The app opens normally from now on

If the dialog does not show an **Open** button:

1. Go to **System Settings** → **Privacy & Security**
2. Scroll down — you will see: "MacNTFS was blocked because..."
3. Click **Open Anyway**
4. Enter your admin password

---

### Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14.0 Sonoma or later (tested on macOS 26 Tahoe) |
| Architecture | Apple Silicon (M1/M2/M3/M4/M5) — Intel untested |
| FUSE-T | 1.0+ |
| ntfs-3g | 2022+ (compiled from source, patched for fuse_t.framework) |
| Homebrew | Any recent version |
| Xcode | Required only to build from source |

### Dependencies

| Component | Purpose | Source |
|-----------|---------|--------|
| [FUSE-T](https://www.fuse-t.org/) | Userspace filesystem via NFS loopback — no kext required | fuse-t.org |
| [ntfs-3g](https://github.com/tuxera/ntfs-3g) | NTFS read/write driver | Built from source, patched |
| [Homebrew](https://brew.sh/) | Package manager for build tools | brew.sh |

> **Why not macFUSE?** macFUSE requires a kernel extension that cannot load on macOS 26 Tahoe (arm64) with SIP enabled. FUSE-T achieves the same result without a kext using a Go-based NFS loopback server (`go-nfsv4`).

---

### Troubleshooting

**"ntfs-3g not found"**
Make sure ntfs-3g is at `/opt/homebrew/bin/ntfs-3g`. If it's elsewhere, adjust the path in the sudoers file.

**"Operation not permitted" on `/dev/diskXsY`**
Full Disk Access is not granted to MacNTFS. See Step 5.

**"sudo: a password is required"**
The sudoers file is not configured. Run Step 4 again.

**"No such file or directory" on mount**
The disk disconnected between DA detection and the mount attempt. Click Mount again — DA re-detects quickly.

**"Device not configured"**
`diskutil unmount force` ran but the device became unavailable. This happens if DA already unmounted it. Click Mount again immediately after seeing the disk reappear.

**Mount succeeds but UI shows "Read-Only" again**
Likely a permissions issue with Full Disk Access (Step 5). Also verify the NOPASSWD sudoers entries (Step 4).

**Drive appears mounted in terminal but Finder doesn't show it**
Fuse-T mounts appear as NFS volumes. Open Finder → Go → Go to Folder → type `/Volumes/DRIVENAME`.

---

## Español

### El Problema

macOS detecta discos con formato NTFS (Windows) pero los monta como **solo lectura**. Puedes ver tus archivos pero no puedes modificar, copiar ni eliminar nada. Las alternativas son reformatear el disco (perdiendo todos los datos) o comprar software comercial costoso.

### La Solución

MacNTFS re-monta discos NTFS con soporte completo de escritura usando `ntfs-3g` y `FUSE-T`. Un solo clic — sin reformatear, sin pérdida de datos. El disco sigue siendo totalmente compatible con Windows.

**Confirmado funcionando en macOS 26 Tahoe (arm64 Apple Silicon):** copiar, pegar, mover y eliminar archivos en discos NTFS.

### Funcionalidades

| Funcionalidad | Descripción |
|---------------|-------------|
| **Detección automática** | Detecta discos externos al instante cuando se conectan por USB o hub |
| **Identificación NTFS** | Identifica el tipo de sistema de archivos y resalta discos NTFS con estado visual |
| **Montaje R/W con un clic** | Re-monta discos NTFS con soporte completo de escritura vía ntfs-3g + FUSE-T |
| **Estado estable** | Tolerante al ciclo de DiskArbitration — el estado "montado" persiste en la UI |
| **Notificaciones nativas** | Notificaciones de macOS al conectar o desconectar discos |
| **Logs en tiempo real** | Panel de registro con botón de copiar al portapapeles |
| **Modo oscuro** | Soporte completo para temas Sistema, Claro y Oscuro |
| **Bilingüe** | Interfaz en inglés y español con cambio de idioma instantáneo |
| **Indicador de almacenamiento** | Barra visual mostrando la capacidad del disco |
| **Barra de estado** | Barra inferior persistente con conteo de discos y estado de montaje |

### Cómo Funciona

```
Conectar disco NTFS por USB
        │
        ▼
MacNTFS detecta el disco automáticamente (DiskArbitration API)
        │
        ▼
Clic en "Montar con Escritura"
        │
        ▼
La app desmonta el montaje solo lectura → re-monta vía ntfs-3g + FUSE-T (NFS loopback)
        │
        ▼
Acceso completo — copiar, mover, renombrar, eliminar
        │
        ▼
Expulsar de forma segura → el disco funciona en Windows exactamente igual
```

### Por qué FUSE-T en vez de macFUSE

macFUSE requiere una extensión de kernel (kext) que **no puede cargar en macOS 26 Tahoe en Apple Silicon** debido a la Protección de Integridad del Sistema y la nueva arquitectura FSKit. FUSE-T usa un mecanismo NFS loopback en lugar de un kext — sin extensión de kernel, sin desactivar SIP.

---

### Instalación (Guía Completa)

Esta es una herramienta para desarrolladores y usuarios avanzados. La configuración completa requiere Terminal. Sigue cada paso exactamente.

#### Paso 1 — Instalar Homebrew (si no está instalado)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Después de la instalación, sigue los "Next steps" que aparecen en la terminal para agregar Homebrew al PATH.

#### Paso 2 — Instalar FUSE-T

Descargar e instalar desde el sitio oficial: **https://www.fuse-t.org/**

O vía Homebrew cask:

```bash
brew install --cask fuse-t
```

Verificar instalación:

```bash
ls /Library/Frameworks/fuse_t.framework && echo "FUSE-T OK"
```

#### Paso 3 — Compilar ntfs-3g desde fuente

ntfs-3g debe compilarse desde fuente y parchearse para enlazar con `fuse_t.framework` en lugar del `libfuse` por defecto. El binario estándar `brew install ntfs-3g` enlaza con macFUSE y no funcionará.

```bash
# Instalar dependencias de compilación
brew install autoconf automake libtool pkg-config

# Clonar fuente ntfs-3g
git clone https://github.com/tuxera/ntfs-3g.git
cd ntfs-3g

# Configurar y compilar contra fuse_t.framework
./autogen.sh
./configure \
  CFLAGS="-I/Library/Frameworks/fuse_t.framework/Headers" \
  LDFLAGS="-F/Library/Frameworks -framework fuse_t" \
  --disable-ntfsprogs \
  --disable-crypto
make -j$(sysctl -n hw.logicalcpu)
sudo make install
```

Parchear el binario instalado para usar la ruta de librería correcta:

```bash
sudo install_name_tool -change \
  /usr/local/lib/libfuse.2.dylib \
  /Library/Frameworks/fuse_t.framework/fuse_t \
  /opt/homebrew/bin/ntfs-3g
```

Verificar:

```bash
otool -L /opt/homebrew/bin/ntfs-3g | grep fuse
# Debe mostrar: /Library/Frameworks/fuse_t.framework/fuse_t
```

Prueba de montaje (reemplaza `diskXsY` con tu identificador real de `diskutil list`):

```bash
sudo diskutil unmount force /dev/diskXsY
sudo mkdir -p /Volumes/NTFSTEST
sudo /opt/homebrew/bin/ntfs-3g /dev/diskXsY /Volumes/NTFSTEST \
  -o local,allow_other,auto_xattr,big_writes,noatime,remove_hiberfile
mount | grep NTFSTEST   # Debe mostrar: fuse-t:/... (nfs)
echo "prueba escritura" > /Volumes/NTFSTEST/test.txt && echo "ESCRITURA OK"
```

#### Paso 4 — Configurar privilegios sudo (NOPASSWD)

La app llama `sudo` vía `Process()` — no aparece ningún diálogo de contraseña, no se requiere terminal. Esto requiere entradas NOPASSWD para los binarios específicos que se usan.

```bash
sudo tee /etc/sudoers.d/ntfs3g << 'EOF'
ALL ALL=(ALL) NOPASSWD: /usr/bin/pkill
ALL ALL=(ALL) NOPASSWD: /usr/sbin/diskutil
ALL ALL=(ALL) NOPASSWD: /bin/mkdir
ALL ALL=(ALL) NOPASSWD: /opt/homebrew/bin/ntfs-3g
ALL ALL=(ALL) NOPASSWD: /sbin/umount
EOF
sudo chmod 440 /etc/sudoers.d/ntfs3g
sudo visudo -c && echo "sudoers OK"
```

> **Nota de seguridad:** Estas entradas permiten a cualquier usuario admin en este Mac ejecutar esos cinco binarios específicos como root sin contraseña. Están limitadas a rutas exactas — sin comandos con wildcard.

#### Paso 5 — Otorgar Acceso Total al Disco a MacNTFS

macOS requiere permiso explícito de Acceso Total al Disco para apps que acceden a dispositivos de disco raw (`/dev/diskXsY`).

1. Abrir **Ajustes del Sistema** → **Privacidad y Seguridad** → **Acceso Total al Disco**
2. Hacer clic en el botón **+**
3. Navegar y seleccionar **MacNTFS.app**
4. Activar el interruptor a **ON**
5. Reiniciar MacNTFS si ya estaba abierto

Sin esto, ntfs-3g fallará con `Operation not permitted` al intentar leer la partición NTFS.

#### Paso 6 — Compilar y ejecutar la app

**Desde fuente:**

```bash
git clone https://github.com/JhojanAlexanderCalambasRamirez/MacNTFS.git
cd MacNTFS
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS -configuration Release build
```

**O abrir en Xcode:**

```bash
open MacNTFS.xcodeproj
```

Luego compilar con `⌘B` y ejecutar con `⌘R`.

---

### Primera Ejecución — Gatekeeper de macOS

Como la app no está firmada con certificado de Apple Developer, macOS la bloqueará en la primera ejecución. Esto es normal y seguro.

1. Ir a la carpeta **Applications** en Finder
2. **Click derecho** (Control+click) sobre **MacNTFS.app** — NO hacer doble click
3. Hacer clic en **Abrir** en el menú contextual
4. Aparecerá un diálogo: "macOS no puede verificar al desarrollador" → Hacer clic en **Abrir**
5. Listo. La app abrirá normalmente de ahora en adelante

Si no aparece el botón **Abrir**:

1. Ir a **Ajustes del Sistema** → **Privacidad y Seguridad**
2. Scroll hacia abajo — verás: "Se bloqueó MacNTFS porque..."
3. Hacer clic en **Abrir de todas formas**
4. Ingresar contraseña de administrador

---

### Solución de Problemas

**"ntfs-3g not found"**
Verificar que ntfs-3g esté en `/opt/homebrew/bin/ntfs-3g`. Si está en otra ruta, ajustar en el archivo sudoers.

**"Operation not permitted" en `/dev/diskXsY`**
No se ha otorgado Acceso Total al Disco a MacNTFS. Ver Paso 5.

**"sudo: se requiere contraseña"**
El archivo sudoers no está configurado. Ejecutar el Paso 4 nuevamente.

**"No such file or directory" al montar**
El disco se desconectó entre la detección DA y el intento de montaje. Hacer clic en Montar de nuevo — DA lo re-detecta rápidamente.

**"Device not configured"**
`diskutil unmount force` se ejecutó pero el dispositivo quedó no disponible. Hacer clic en Montar inmediatamente después de que el disco reaparezca.

**El disco aparece montado en terminal pero Finder no lo muestra**
FUSE-T monta como volúmenes NFS. Abrir Finder → Ir → Ir a la carpeta → escribir `/Volumes/NOMBRE_DISCO`.

---

## Tech Stack / Stack Tecnológico

| Technology | Purpose |
|------------|---------|
| **Swift 6** | Language with strict concurrency |
| **SwiftUI** | Native macOS declarative UI |
| **DiskArbitration.framework** | Real-time disk connect/disconnect events |
| **FUSE-T** | Userspace filesystem via NFS loopback (no kext) |
| **ntfs-3g** | NTFS read/write driver (compiled from source, patched) |
| **sudo + Process()** | Privileged operations — preserves app TCC responsible process |
| **UserNotifications** | Native macOS notification system |

## Project Structure / Estructura del Proyecto

```
MacNTFS/
├── App/
│   └── MacNTFSApp.swift              # Entry point, settings, theme, onboarding
├── Models/
│   ├── ExternalDisk.swift
│   └── FileOperation.swift
├── Services/
│   ├── DiskDetectionService.swift    # DiskArbitration monitoring + DA cycling guard
│   ├── NTFSMountService.swift        # ntfs-3g mount/unmount via sudo Process()
│   ├── FileOperationService.swift    # Copy, move, rename, delete
│   ├── LogService.swift              # Log aggregation
│   └── NotificationService.swift    # Native macOS notifications
├── ViewModels/
│   ├── DiskViewModel.swift           # Mount state, DA cycling protection
│   └── FileOperationViewModel.swift
├── Views/
│   ├── ContentView.swift             # Main layout + status bar
│   ├── DiskListView.swift            # Sidebar with disk cards
│   ├── FileManagerView.swift         # File browser
│   ├── LogView.swift                 # Log inspector with copy button
│   └── OnboardingView.swift          # First-launch setup wizard
└── Helpers/
    ├── ShellExecutor.swift
    └── LocalizationManager.swift     # EN/ES translations
```

## Building / Compilar

```bash
# Release build
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS -configuration Release build

# Create .dmg for distribution
chmod +x scripts/create-dmg.sh
mkdir -p dist
./scripts/create-dmg.sh 1.0.0
```

## License / Licencia

[MIT](LICENSE) — Alexander Calambas

## Contact / Contacto

- **LinkedIn:** [j4cr](https://www.linkedin.com/in/j4cr/)
- **GitHub:** [JhojanAlexanderCalambasRamirez](https://github.com/JhojanAlexanderCalambasRamirez)
- **Email:** alexandercalambas23@gmail.com
