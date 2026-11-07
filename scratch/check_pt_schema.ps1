$headers = @{
  "apikey" = "sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
  "Authorization" = "Bearer sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6"
}
$spec = Invoke-RestMethod -Uri "https://umxyotycpumkkpjwfvlz.supabase.co/rest/v1/" -Headers $headers
$ptDef = $spec.definitions.phuong_tien
Write-Host "phuong_tien columns:" ($ptDef.properties.PSObject.Properties.Name -join ", ")
foreach ($prop in $ptDef.properties.PSObject.Properties) {
  Write-Host $prop.Name ":" $prop.Value.type
}
