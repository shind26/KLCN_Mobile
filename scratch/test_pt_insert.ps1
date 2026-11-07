$headers = @{
  "apikey" = "sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Authorization" = "Bearer sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Content-Type" = "application/json"
  "Prefer" = "return=representation"
}
$json = '{"ma_phuong_tien":"PT_TEST_99","ma_khach":"KH_DUYEN","ma_phong":"P203","loai_xe":"Xe máy","bien_so_xe":"59-X1 999.99","trang_thai":"ChoDuyet"}'

try {
  $res = Invoke-RestMethod -Uri "https://umxyotycpumkkpjwfvlz.supabase.co/rest/v1/phuong_tien" -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
  Write-Host "Insert OK:" ($res | ConvertTo-Json -Compress)
} catch {
  Write-Host "Insert error: $_"
  if ($_.Exception.Response) {
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    Write-Host "Response body:" $reader.ReadToEnd()
  }
}
