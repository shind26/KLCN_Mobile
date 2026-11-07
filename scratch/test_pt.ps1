$headers = @{
  "apikey" = "sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Authorization" = "Bearer sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Content-Type" = "application/json"
}
try {
  $res = Invoke-RestMethod -Uri "https://umxyotycpumkkpjwfvlz.supabase.co/rest/v1/phuong_tien?select=*" -Headers $headers
  Write-Host "Select phuong_tien OK, count:" $res.Count
} catch {
  Write-Host "Select error: $_"
}
