param(
    [switch]$o,
    [int]$t = 31,
    [switch]$h
)

# Set variables
$PYTHON = "python"
$PIP = "pip"
$VIRTUAL_ENV_DIR = ".virtualenvs/carr_script"
$USE_VENV = $true
$INTERNET_ACCESS = $false
$CARR_LEAD_DAYS = $t
$whl = Get-ChildItem -Path carr-*.whl | Select-Object -First 1
Write-Host "Found Carr wheel file: $($whl.FullName)"

function Print-Usage {
    Write-Host "Usage: .\carr_script.ps1 [-o] [-t days]"
    Write-Host "  -o : download dependencies from internet if connectivity is there"
    Write-Host "  -t : Lead time in days, between 31 and 825, to check for expiry of certificates. Default is 31 days."
    Write-Host "  -h : prints this message"
}

function Check-LeadDays($days) {
    if ($days -lt 31 -or $days -gt 825) {
        Write-Host "Error: The days argument should be between 31 and 825."
        Print-Usage
        exit 1
    }
}

function Check-InternetAccess {
    Write-Host "Checking Internet access ..."
    try {
        $pingResult = Test-Connection -ComputerName "www.pypi.org" -Count 1 -Quiet
        $script:INTERNET_ACCESS = $pingResult
        if ($INTERNET_ACCESS) {
            Write-Host "Internet access is available."
            $script:USE_OFFLINE = $false
        } else {
            Write-Host "Internet access is not available. Switching to offline mode."
            $script:USE_OFFLINE = $true
        }
    } catch {
        Write-Host "Error checking internet access. Assuming offline mode."
        $script:INTERNET_ACCESS = $false
        $script:USE_OFFLINE = $true
    }
}

function Install-Pip3 {
    Write-Host "Installing $PIP ..."
    try {
        # Use ensurepip to bootstrap pip
        & $PYTHON -m ensurepip --upgrade
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$PIP installed successfully using ensurepip."
        } else {
            Write-Host "Failed to install pip using ensurepip."
            exit 1
        }
    } catch {
        Write-Host "Failed to install pip using ensurepip."
        exit 1
    }

    # Upgrade pip to the desired version
    try {
        Write-Host "Upgrading $PIP to version 24.2 ..."
        & $PYTHON -m pip install --upgrade pip==24.2
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$PIP upgraded to version 24.2 successfully."
        } else {
            Write-Host "Failed to upgrade pip to version 24.2."
            exit 1
        }
    } catch {
        Write-Host "Failed to upgrade pip to version 24.2. Please check your internet connection or Python setup."
        exit 1
    }
}

function Install-Virtualenv {
    Write-Host "Installing virtualenv ..."
    if (-not $whl) {
        Write-Host "Error: virtualenv wheel file not found in the wheels directory."
        Write-Host "Ensure that the 'wheels' directory contains the required .whl file."
        exit 1
    }
    & $PIP install --root-user-action=ignore --no-index --find-links=wheels $whl.FullName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtualenv installed successfully"
    } else {
        Write-Host "Virtualenv installation failed."
        exit 1
    }
}

function Check-PythonVersion {
    $pythonPath = Get-Command $PYTHON -ErrorAction SilentlyContinue
    if (-not $pythonPath) {
        Write-Host "$PYTHON is not installed"
        exit 1
    }
    $pythonVersion = & $PYTHON --version 2>&1
    $versionMatch = $pythonVersion -match "(\d+)\.(\d+)\.(\d+)"
    if (-not $versionMatch) {
        Write-Host "Could not determine Python version."
        exit 1
    }
    $minor = [int]$Matches[2]
    Write-Host "Python version is $pythonVersion"
    if ($minor -lt 8) {
        Write-Host "Installed python3 version is $pythonVersion. It should be equal or greater than 3.8 version"
        exit 1
    }
    if (-not $INTERNET_ACCESS -and $minor -gt 12) {
        Write-Host "Installed python3 version is $pythonVersion. It should be between 3.8 and 3.12 version"
        exit 1
    }
}

function Check-InstallPip {
    try {
        & $PYTHON -m pip -h > $null 2>&1
        Write-Host "Pip3 is installed"
    } catch {
        Write-Host "Pip3 is not installed. Pip3 is getting installed ..."
        Install-Pip3
    }
}

function Check-InstallVirtualenv {
    try {
        & $PYTHON -m venv -h > $null 2>&1
        $venvInstalled = $true
    } catch {
        $venvInstalled = $false
    }
    try {
        & $PYTHON -m ensurepip -h > $null 2>&1
        $ensurepipInstalled = $true
    } catch {
        $ensurepipInstalled = $false
    }
    if ($venvInstalled -and $ensurepipInstalled) {
        Write-Host "venv and ensurepip are installed"
        return
    }
    try {
        & $PYTHON -m virtualenv -h > $null 2>&1
        Write-Host "virtualenv is installed"
    } catch {
        Write-Host "virtualenv is not installed. virtualenv is getting installed ..."
        Install-Virtualenv
    }
}

function Check-VirtualenvDir {
    if (Test-Path $VIRTUAL_ENV_DIR) {
        # Remove if needed (no direct stat equivalent, so always keep for now)
        # You can add timestamp logic if needed
        return
    }
}

function Create-VirtualEnv {
    Check-VirtualenvDir
    if (Test-Path $VIRTUAL_ENV_DIR) {
        Write-Host "virtualenv : $VIRTUAL_ENV_DIR exists."
        return
    }
    New-Item -ItemType Directory -Force -Path $VIRTUAL_ENV_DIR | Out-Null
    if ($USE_VENV) {
        & $PYTHON -m venv $VIRTUAL_ENV_DIR
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Virtual environment created using venv."
            return
        }
    }
    & $VIRTUALENV -p $PYTHON $VIRTUAL_ENV_DIR
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtual environment created."
    } else {
        Write-Host "Failed to create virtualenv"
        exit 1
    }
}

function Activate-VirtualEnv {
    $activateScript = Join-Path $VIRTUAL_ENV_DIR "Scripts/activate"
    if (-not (Test-Path $activateScript)) {
        Write-Host "Failed to activate virtualenv. Activation script not found."
        exit 1
    }
    Write-Host "Activating virtual environment..."
    & $activateScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtual environment activated."
    } else {
        Write-Host "Failed to activate virtualenv."
        exit 1
    }
}
function Ensure-Pip-In-VirtualEnv {
    $venvPip = Join-Path $VIRTUAL_ENV_DIR "Scripts/pip"
    if (-not (Test-Path $venvPip)) {
        Write-Host "pip is not available in the virtual environment. Installing pip..."
        & $PYTHON -m ensurepip --upgrade
        if ($LASTEXITCODE -eq 0) {
            Write-Host "pip installed successfully in the virtual environment."
        } else {
            Write-Host "Failed to install pip in the virtual environment."
            exit 1
        }
    } else {
        Write-Host "pip is already available in the virtual environment."
    }
}
function Carr-Installed {
    $carrPath = Join-Path $VIRTUAL_ENV_DIR "Scripts/carr"
    if (Test-Path $carrPath) {
        Write-Host "Carr package is already installed."
        return $true
    }
    return $false
}

function Install-CarrWhl {
    if (Carr-Installed) {
        return
    }
    if (-not $whl) {
        Write-Host "Error: Carr wheel file not found in the wheels directory."
        Write-Host "Ensure that the 'wheels' directory contains the required .whl file."
        exit 1
    }

    if ($INTERNET_ACCESS) {
        Write-Host "Installing Carr package online..."
        & pip install $whl.FullName
    } else {
        Write-Host "Installing Carr package offline..."
        ##pip download --platform win_amd64 --only-binary=:all: --dest=wheels carr==$whl.FullName
        ##Use above command to download the wheel file if needed then repack. 
        & pip install --no-index --find-links wheels $whl.FullName
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Carr package installed successfully."
    } else {
        Write-Host "Failed to install Carr package."
        exit 1
    }
}

# Argument handling
if ($h) {
    Print-Usage
    exit 0
}
if ($o) {
    $USE_OFFLINE = $false
}
Check-LeadDays $t
$env:CARR_LEAD_DAYS = $t

# Main script logic
Check-InternetAccess

if ($USE_OFFLINE) {
    Write-Host "Script is running in offline mode"
} else {
    Write-Host "Script is running in online mode"
}
Check-PythonVersion
Check-InstallPip
Check-InstallVirtualenv
Create-VirtualEnv

# Activate the virtual environment
Activate-VirtualEnv

# Ensure pip is available in the virtual environment
Ensure-Pip-In-VirtualEnv

# Install the Carr package in the virtual environment
Install-CarrWhl

# Run the Carr script from the virtual environment
& "$VIRTUAL_ENV_DIR/Scripts/carr"
