param(
    [switch]$o,
    [int]$t = 31,
    [switch]$h
)

# Set variables
$PYTHON = "python3"
$PIP = "pip3"
$VIRTUALENV = "virtualenv"
$VIRTUAL_ENV_DIR = ".virtualenvs/carr_script"
$USE_VENV = $false
$INTERNET_ACCESS = $false
$USE_OFFLINE = $true
$CARR_LEAD_DAYS = $t

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
        $response = Invoke-WebRequest -Uri "https://www.pypi.org" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $GLOBALS:INTERNET_ACCESS = $true
        }
    } catch {
        $GLOBALS:INTERNET_ACCESS = $false
    }
    Write-Host "Internet access is $INTERNET_ACCESS"
}

function Install-Pip3 {
    Write-Host "Installing $PIP ..."
    # Try ensurepip first
    try {
        & $PYTHON -m ensurepip --upgrade
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$PIP installed successfully using ensurepip"
            return
        }
    } catch {
        Write-Host "ensurepip not available, trying get-pip.py"
    }
    # Fallback to get-pip.py if available
    if (Test-Path "./get-pip.py") {
        & $PYTHON ./get-pip.py pip==24.2 --no-setuptools --no-wheel --no-index --find-links=./wheels
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$PIP installed successfully using get-pip.py"
            return
        }
    }
    Write-Host "$PIP installation failed."
    exit 1
}

function Install-Virtualenv {
    Write-Host "Installing virtualenv ..."
    & $PIP install --root-user-action=ignore --no-index --find-links=./wheels ./wheels/virtualenv-*-py3-none-any.whl
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$VIRTUALENV installed successfully"
    } else {
        Write-Host "$VIRTUALENV installation failed."
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
        $GLOBALS:USE_VENV = $true
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
    $activateScript = Join-Path $VIRTUAL_ENV_DIR "bin/activate"
    if (-not (Test-Path $activateScript)) {
        Write-Host "Failed to activate virtualenv"
        exit 1
    }
    & $activateScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtual environment activated."
    } else {
        Write-Host "Failed to activate virtualenv"
        exit 1
    }
}

function Carr-Installed {
    $carrPath = Join-Path $VIRTUAL_ENV_DIR "bin/carr"
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
    if ($INTERNET_ACCESS) {
        & $PIP install ./carr-*-py3-none-any.whl
    } else {
        & $PIP install --no-index --find-links ./wheels/ ./carr-*-py3-none-any.whl
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Carr package installed successfully."
    } else {
        Write-Host "Failed to install carr package"
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
if (-not $USE_OFFLINE) {
    Check-InternetAccess
} else {
    Write-Host "Script is running in offline mode"
}

Check-PythonVersion
Check-InstallPip
Check-InstallVirtualenv
Create-VirtualEnv

# Activate virtual environment (PowerShell: just run scripts in venv/bin)
# You may need to adjust this for your shell/environment
# For most scripts, you can just use the full path to the binary

Install-CarrWhl

# Run carr script
& "$VIRTUAL_ENV_DIR/bin/carr"
