# Tiny static server for a packaged web build. usage: powershell -File tools\serve_web.ps1 -Root <dir> [-Port 8099]
param([string]$Root = "site-assets/play", [int]$Port = 8099)
$Root = (Resolve-Path $Root).Path
$mime = @{ ".html" = "text/html"; ".js" = "text/javascript"; ".wasm" = "application/wasm"; ".pck" = "application/octet-stream"; ".png" = "image/png"; ".json" = "application/json"; ".css" = "text/css" }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Output "serving $Root on http://127.0.0.1:$Port/"
while ($listener.IsListening) {
	$ctx = $listener.GetContext()
	$path = $ctx.Request.Url.AbsolutePath.TrimStart("/")
	if ($path -eq "") { $path = "index.html" }
	$file = Join-Path $Root $path
	if ((Test-Path $file -PathType Leaf) -and ($file.StartsWith($Root))) {
		$bytes = [System.IO.File]::ReadAllBytes($file)
		$ext = [System.IO.Path]::GetExtension($file).ToLower()
		$ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
		$ctx.Response.AddHeader("Cache-Control", "no-store")
		$ctx.Response.ContentLength64 = $bytes.Length
		$ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
	} else {
		$ctx.Response.StatusCode = 404
	}
	$ctx.Response.Close()
}
