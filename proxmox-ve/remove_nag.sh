#!/usr/bin/env bash
set -euo pipefail

TARGETS=(
  "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
  "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.min.js"
)

RESTART_REQUIRED=0

for FILE in "${TARGETS[@]}"; do
  if [[ ! -f "$FILE" ]]; then
    echo "Skip (not found): $FILE"
    continue
  fi

  echo "==> $FILE"

  # Если "No valid subscription" уже отсутствует — считаем, что патч применён (или файл другой версии)
  if ! grep -q "No valid subscription" "$FILE"; then
    echo "Already patched (No valid subscription not found)."
    continue
  fi

  SHA_FULL="$(sha256sum "$FILE" | awk '{print $1}')"
  SHA_SHORT="${SHA_FULL:0:12}"
  BACKUP="${FILE}.${SHA_SHORT}.bak"

  if [[ -f "$BACKUP" ]]; then
    echo "Backup exists: $BACKUP"
  else
    echo "Creating backup: $BACKUP"
    cp -a "$FILE" "$BACKUP"
  fi

  perl -0777 -i -pe '
    sub find_checked_param {
      my ($s) = @_;

      my $needle1 = "checked_command:function";
      my $needle2 = "checked_command: function";
      my $start = index($s, $needle1);
      $start = index($s, $needle2) if $start < 0;
      return "" if $start < 0;

      my $fpos = index($s, "function", $start);
      return "" if $fpos < 0;

      my $lpar = index($s, "(", $fpos);
      return "" if $lpar < 0;

      my $rpar = index($s, ")", $lpar);
      return "" if $rpar < 0;

      my $param = substr($s, $lpar + 1, $rpar - $lpar - 1);
      $param =~ s/^\s+|\s+$//g;

      # Важно: \$ чтобы Perl не подставлял $] (версию Perl) внутрь character class
      return ($param =~ /\A[A-Za-z_\$][A-Za-z0-9_\$]*\z/) ? $param : "";
    }

    sub find_call_range_extmsgshow {
      my ($s) = @_;
      my $len = length($s);

      my $needle = "No valid subscription";
      my $npos = index($s, $needle);
      die "No valid subscription not found (should have been checked)\n" if $npos < 0;

      # Найти ближайший Ext.Msg.show перед ним
      my $show = rindex($s, "Ext.Msg.show", $npos);
      die "Ext.Msg.show not found before No valid subscription\n" if $show < 0;

      # Найти открывающую скобку вызова
      my $lpar = index($s, "(", $show);
      die "Cannot find ( after Ext.Msg.show\n" if $lpar < 0;

      # Сканируем до закрытия скобок вызова: Ext.Msg.show( ... )
      my $depth = 0;

      my ($in_sq,$in_dq,$in_bt,$in_lc,$in_bc,$esc) = (0,0,0,0,0,0);

      for (my $i = $lpar; $i < $len; $i++) {
        my $c  = substr($s,$i,1);
        my $c2 = ($i+1<$len)?substr($s,$i,2):"";

        if ($in_lc) { $in_lc = 0 if $c eq "\n"; next; }
        if ($in_bc) { if ($c2 eq "*/") { $in_bc=0; $i++; } next; }

        if ($in_sq) { if($esc){$esc=0;next;} if($c eq "\\"){ $esc=1;next;} $in_sq=0 if $c eq "\x27"; next; }
        if ($in_dq) { if($esc){$esc=0;next;} if($c eq "\\"){ $esc=1;next;} $in_dq=0 if $c eq "\x22"; next; }
        if ($in_bt) { if($esc){$esc=0;next;} if($c eq "\\"){ $esc=1;next;} $in_bt=0 if $c eq "\x60"; next; }

        if ($c2 eq "//") { $in_lc=1; $i++; next; }
        if ($c2 eq "/*") { $in_bc=1; $i++; next; }
        if ($c eq "\x27") { $in_sq=1; next; }
        if ($c eq "\x22") { $in_dq=1; next; }
        if ($c eq "\x60") { $in_bt=1; next; }

        if ($c eq "(") { $depth++; next; }
        if ($c eq ")") {
          $depth--;
          if ($depth == 0) {
            # Захватим хвост до конца statement: optional spaces + ;
            my $j = $i + 1;
            while ($j < $len && substr($s,$j,1) =~ /\s/) { $j++; }
            if ($j < $len && substr($s,$j,1) eq ";") { $j++; }
            return ($show, $j);
          }
          next;
        }
      }

      die "Unbalanced parentheses while scanning Ext.Msg.show call\n";
    }

    # Определим имя команды для вызова: orig_cmd (pretty) или параметр (min)
    my $cmd = "orig_cmd";
    my $p = find_checked_param($_);
    $cmd = $p if $p ne "";

    my ($from,$to) = find_call_range_extmsgshow($_);

    # Определим отступ (для красивой версии). Для min он обычно пустой.
    my $indent = "";
    my $nl = rindex($_, "\n", $from);
    if ($nl >= 0) {
      my $k = $nl + 1;
      while ($k < length($_)) {
        my $ch = substr($_,$k,1);
        last unless $ch =~ /[ \t]/;
        $indent .= $ch;
        $k++;
      }
    }

    substr($_, $from, $to-$from) = $indent . $cmd . "();";
  ' "$FILE"

  # Если после патча строка всё ещё есть — значит что-то не так
  if grep -q "No valid subscription" "$FILE"; then
    echo "ERROR: Patch did not remove nag block (string still present). Restoring backup." >&2
    cp -a "$BACKUP" "$FILE"
    exit 1
  fi

  echo "Patched. Original sha256: $SHA_FULL"
  RESTART_REQUIRED=1
done

if [[ "$RESTART_REQUIRED" -eq 1 ]]; then
  echo "Restarting pveproxy..."
  systemctl restart pveproxy
  echo "pveproxy restarted."
else
  echo "No changes made. Restart not required."
fi

