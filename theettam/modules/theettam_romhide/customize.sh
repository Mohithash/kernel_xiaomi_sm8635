SKIPUNZIP=0
ui_print "- Theettam ROM Prop Hide v1.0.1"
ui_print "- resetprop: strips VoltageOS props + deletes sys.oem_unlock_allowed"
set_perm_recursive "$MODPATH" 0 0 0755 0644
chmod 0755 "$MODPATH/hideprops.sh" "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" 2>/dev/null
