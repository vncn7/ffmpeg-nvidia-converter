# Load necessary .NET assemblies for GUI components
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Function to generate output filename with _converted suffix
function Get-ConvertedOutputPath {
    param([string]$inputPath)
    
    $directory = [System.IO.Path]::GetDirectoryName($inputPath)
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    $extension = [System.IO.Path]::GetExtension($inputPath)
    
    return [System.IO.Path]::Combine($directory, "$filename`_converted$extension")
}

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "ffmpeg h264 GPU Accelerated Converter"
$form.Size = New-Object System.Drawing.Size(400,300)  # Form dimensions
$form.StartPosition = "CenterScreen"  # Position form in the center of the screen
$form.FormBorderStyle = "FixedSingle"  # Prevent resizing of the form
$form.MaximizeBox = $false  # Disable maximize button

# Input file label
$inputLabel = New-Object System.Windows.Forms.Label
$inputLabel.Location = New-Object System.Drawing.Point(10,20)
$inputLabel.Size = New-Object System.Drawing.Size(70,20)
$inputLabel.Text = "Input File:"
$form.Controls.Add($inputLabel)

# Input file textbox
$inputTextBox = New-Object System.Windows.Forms.TextBox
$inputTextBox.Location = New-Object System.Drawing.Point(90,20)
$inputTextBox.Size = New-Object System.Drawing.Size(200,20)
$form.Controls.Add($inputTextBox)

# Input file browse button
$inputButton = New-Object System.Windows.Forms.Button
$inputButton.Location = New-Object System.Drawing.Point(300,20)
$inputButton.Size = New-Object System.Drawing.Size(80,20)
$inputButton.Text = "Browse"
# Browse file dialog for input file
$inputButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Video Files (*.mp4;*.avi;*.mkv)|*.mp4;*.avi;*.mkv|All Files (*.*)|*.*"
    if ($openFileDialog.ShowDialog() -eq "OK") {
        $inputTextBox.Text = $openFileDialog.FileName  # Set selected file to textbox
        $outputTextBox.Text = Get-ConvertedOutputPath $openFileDialog.FileName  # Auto-generate output filename
    }
})
$form.Controls.Add($inputButton)

# Output file label
$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Location = New-Object System.Drawing.Point(10,50)
$outputLabel.Size = New-Object System.Drawing.Size(70,20)
$outputLabel.Text = "Output File:"
$form.Controls.Add($outputLabel)

# Output file textbox
$outputTextBox = New-Object System.Windows.Forms.TextBox
$outputTextBox.Location = New-Object System.Drawing.Point(90,50)
$outputTextBox.Size = New-Object System.Drawing.Size(200,20)
$form.Controls.Add($outputTextBox)

# Output file browse button
$outputButton = New-Object System.Windows.Forms.Button
$outputButton.Location = New-Object System.Drawing.Point(300,50)
$outputButton.Size = New-Object System.Drawing.Size(80,20)
$outputButton.Text = "Browse"
# Browse file dialog for output file
$outputButton.Add_Click({
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveFileDialog.Filter = "MP4 Files (*.mp4)|*.mp4|All Files (*.*)|*.*"
    if ($saveFileDialog.ShowDialog() -eq "OK") {
        $outputTextBox.Text = $saveFileDialog.FileName  # Set output file path in textbox
    }
})
$form.Controls.Add($outputButton)

# Global variables to hold the conversion process and timer
$global:conversionProcess = $null
$global:conversionTimer = $null

# Function to update button states based on process status
function Update-ButtonStates {
    if ($global:conversionProcess -and -not $global:conversionProcess.HasExited) {
        $convertButton.Enabled = $false  # Disable convert button during processing
        $cancelButton.Enabled = $true  # Enable cancel button
    } else {
        $convertButton.Enabled = $true  # Enable convert button
        $cancelButton.Enabled = $false  # Disable cancel button
    }
}

# Function to stop the conversion process and update UI
function Stop-ConversionProcess {
    if ($global:conversionProcess -and -not $global:conversionProcess.HasExited) {
        # Forcefully stop the process if it's running
        $global:conversionProcess | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    if ($global:conversionTimer) {
        $global:conversionTimer.Stop()  # Stop the timer
    }
    # Clean up temporary STDERR file if it exists
    Remove-Item "STDERR" -ErrorAction SilentlyContinue
    $outputField.AppendText("Conversion cancelled.`r`n")
    Update-ButtonStates  # Update button states after cancellation
}

# Convert button configuration
$convertButton = New-Object System.Windows.Forms.Button
$convertButton.Location = New-Object System.Drawing.Point(90,80)
$convertButton.Size = New-Object System.Drawing.Size(100,30)
$convertButton.Text = "Convert"
# Start conversion process when clicked
$convertButton.Add_Click({
    $inputFile = $inputTextBox.Text
    $outputFile = $outputTextBox.Text
    # Validate input file
    if (-not (Test-Path $inputFile)) {
        [System.Windows.Forms.MessageBox]::Show("Input file does not exist", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Update output field with conversion message
    $outputField.AppendText("Converting $inputFile to $outputFile with NVIDIA acceleration...`r`n")
    
    # Start ffmpeg process using NVIDIA hardware acceleration
    $global:conversionProcess = Start-Process ffmpeg -ArgumentList "-hwaccel cuvid -i `"$inputFile`" -c:v h264_nvenc -preset p7 -cq 19 -maxrate 15M -bufsize 30M -c:a aac -b:a 256k -y `"$outputFile`"" -NoNewWindow -RedirectStandardOutput "NUL" -RedirectStandardError "STDERR" -PassThru
    
    # Timer to periodically check process output
    $global:conversionTimer = New-Object System.Windows.Forms.Timer
    $global:conversionTimer.Interval = 1000  # Check every second
    $global:conversionTimer.Add_Tick({
        if (Test-Path "STDERR") {
            # Read the latest stderr output from the process
            $newOutput = Get-Content "STDERR" -Tail 1
            if ($newOutput) {
                $outputField.AppendText("$newOutput`r`n")
                $outputField.ScrollToCaret()  # Auto-scroll to latest output
            }
        }

        # Check if the process has completed
        if ($global:conversionProcess.HasExited) {
            $global:conversionTimer.Stop()
            $errorOutput = Get-Content "STDERR" -Raw
            # Look for successful completion message in stderr output
            if ($errorOutput -match "video:.*audio:.*subtitle:.*other streams:.*global headers:.*muxing overhead:") {
                $outputField.AppendText("Conversion completed successfully.`r`n")
            } else {
                $outputField.AppendText("Conversion failed. Please check the output for details.`r`n")
            }
            Remove-Item "STDERR" -ErrorAction SilentlyContinue  # Clean up stderr file
            Update-ButtonStates  # Update buttons after completion
        }
    })
    $global:conversionTimer.Start()  # Start the timer
    Update-ButtonStates  # Update button states once conversion starts
})
$form.Controls.Add($convertButton)

# Cancel button to stop the conversion process
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(200,80)
$cancelButton.Size = New-Object System.Drawing.Size(100,30)
$cancelButton.Text = "Cancel"
# Stop conversion process when clicked
$cancelButton.Add_Click({
    Stop-ConversionProcess  # Stop the process and timer
})
$form.Controls.Add($cancelButton)

# Output field for displaying conversion progress and messages
$outputField = New-Object System.Windows.Forms.TextBox
$outputField.Location = New-Object System.Drawing.Point(10,120)
$outputField.Size = New-Object System.Drawing.Size(370,130)
$outputField.Multiline = $true  # Allow multiple lines of output
$outputField.ScrollBars = "Vertical"  # Enable vertical scrollbar for large outputs
$outputField.ReadOnly = $true  # Make it read-only to prevent user editing
$form.Controls.Add($outputField)

# Handle form closing event to stop any running processes
$form.Add_FormClosing({
    param($formsender, $e)
    Stop-ConversionProcess  # Stop conversion process if the form is closed
})

# Initialize button states at the start
Update-ButtonStates

# Display the form and start the application
$form.ShowDialog()
