$headers = @{
  "apikey" = "sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Authorization" = "Bearer sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Content-Type" = "application/json"
}
$body = '{"query":"ALTER TABLE phuong_tien DISABLE ROW LEVEL SECURITY;"}'
try {
  $res = Invoke-RestMethod -Uri "https://umxyotycpumkkpjwfvlz.supabase.co/rest/v1/rpc/exec_sql" -Method Post -Headers $headers -Body $body
  Write-Host "RPC OK:" $res
} catch {
  Write-Host "RPC error: $_"
  if ($_.Exception.Response) {
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    Write-Host "Response body:" $reader.ReadToEnd()
  }
}
