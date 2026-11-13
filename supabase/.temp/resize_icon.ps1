Add-Type -AssemblyName System.Drawing

$srcPath = 'G:\misProyectos\GROUP JCK\logo\imagen de loggo de groupjck.png'
$src = [System.Drawing.Image]::FromFile($srcPath)

$sizes = @{
  'mipmap-mdpi' = 48
  'mipmap-hdpi' = 72
  'mipmap-xhdpi' = 96
  'mipmap-xxhdpi' = 144
  'mipmap-xxxhdpi' = 192
}

$baseDir = 'G:\misProyectos\GROUP JCK\app\android\app\src\main\res'

foreach ($folder in $sizes.Keys) {
  $size = $sizes[$folder]
  $outDir = Join-Path $baseDir $folder
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::White)
  
  # Calculate aspect ratio to fit
  $ratio = [Math]::Min($size / $src.Width, $size / $src.Height)
  $newW = [int]($src.Width * $ratio)
  $newH = [int]($src.Height * $ratio)
  $x = [int](($size - $newW) / 2)
  $y = [int](($size - $newH) / 2)
  
  $g.DrawImage($src, $x, $y, $newW, $newH)
  $g.Dispose()
  
  $outPath = Join-Path $outDir 'ic_launcher.png'
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "Saved $outPath ($size x $size)"
}

$src.Dispose()
Write-Output "Done"
