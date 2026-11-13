Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('G:\misProyectos\GROUP JCK\logo\imagen de loggo de groupjck.png')
Write-Output ("Width: " + $img.Width + ", Height: " + $img.Height)
$img.Dispose()
