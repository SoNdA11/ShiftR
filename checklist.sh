#!/usr/bin/env bash
# ShiftR — checklist.sh
# Verificador local do PLAN.md. Somente leitura (não altera o projeto),
# exceto quando chamado com --fix-clean (remove artefatos ignorados).
# Uso:
#   ./checklist.sh                 # tudo
#   ./checklist.sh --phase org     # fases 0-2 (git, estrutura, limpeza)
#   ./checklist.sh --phase docs    # fases 3-4 (README, LICENSE, docs, CI)
#   ./checklist.sh --phase code    # fases 5-7 (refactor, testes, UI)
#   ./checklist.sh --fix-clean     # roda flutter clean + rm de artefatos (pede confirmação)
set -u
# (sem -e de propósito: queremos acumular PASS/FAIL)

PHASE="all"
FIX_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --phase) shift_arg=1 ;;
    --phase=*) PHASE="${arg#--phase=}" ;;
    org|docs|code) PHASE="$arg" ;;
    --fix-clean) FIX_CLEAN=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done
# suporta: ./checklist.sh --phase org
if [[ "${1:-}" == "--phase" ]]; then
  PHASE="${2:-all}"
fi

# Resolve repo root: se pubspec.yaml está em ./shiftr_ble, raiz ainda é pré-Fase-1.
CWD="$(pwd)"
if [[ -f "$CWD/pubspec.yaml" ]]; then
  ROOT="$CWD"
elif [[ -f "$CWD/shiftr_ble/pubspec.yaml" ]]; then
  ROOT="$CWD/shiftr_ble"
  echo "INFO: pubspec encontrado em ./shiftr_ble (pré-Fase-1, Flutter ainda não promovido)."
else
  ROOT="$CWD"
fi
REPO_ROOT="$(dirname "$ROOT/pubspec.yaml" 2>/dev/null || echo "$CWD")"
# PLAN.md e checklist.sh vivem na raiz do futuro repo:
if [[ -f "$CWD/PLAN.md" ]]; then
  REPO_ROOT="$CWD"
fi

PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS+1)); echo "  [OK]   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
warn() { WARN=$((WARN+1)); echo "  [WARN] $1"; }
section() { echo ""; echo "== $1 =="; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- FASE 0-2: org ----------
phase_org() {
  section "ORG — git, estrutura, limpeza (Fases 0-2)"

  # git
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "git repo inicializado em $CWD (branch: $(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'))"
  else
    fail "sem git repo em $CWD — rode: git init -b main (Fase 0)"
  fi

  # estrutura Flutter na raiz?
  if [[ -f "$CWD/pubspec.yaml" && -d "$CWD/lib" ]]; then
    ok "Flutter na raiz (pubspec.yaml + lib/ em $CWD)"
  else
    fail "Flutter NÃO está na raiz — esperado pós-Fase-1 (ainda em shiftr_ble/?)"
  fi
  if [[ -d "$CWD/shiftr_ble" ]]; then
    fail "diretório shiftr_ble/ ainda existe — pendente Fase 1 (mv shiftr_ble/* .)"
  else
    ok "sem ninho shiftr_ble/"
  fi

  # scanner isolado?
  if [[ -f "$CWD/tools/ble_scanner.py" ]]; then
    ok "tools/ble_scanner.py existe"
  else
    fail "tools/ble_scanner.py ausente — pendente Fase 1"
  fi
  if [[ -f "$CWD/scanner.py" ]]; then
    fail "scanner.py ainda na raiz — mover para tools/ (Fase 1)"
  else
    ok "sem scanner.py órfão na raiz"
  fi
  [[ -f "$CWD/tools/requirements.txt" ]] && ok "tools/requirements.txt existe" || fail "tools/requirements.txt ausente (Fase 1)"
  [[ -f "$CWD/tools/README.md" ]] && ok "tools/README.md existe" || fail "tools/README.md ausente (Fase 1)"

  # artefatos
  for d in "build" ".dart_tool" ".idea"; do
    if [[ -e "$REPO_ROOT/$d" || -e "$CWD/$d" || -e "$CWD/shiftr_ble/$d" ]]; then
      fail "artefato presente: $d — rode ./checklist.sh --fix-clean (Fase 2)"
    else
      ok "sem artefato $d/"
    fi
  done
  if ls "$CWD"/*.iml >/dev/null 2>&1 || ls "$CWD/shiftr_ble"/*.iml >/dev/null 2>&1; then
    fail "*.iml presente — remover (Fase 2)"
  else
    ok "sem *.iml"
  fi
  if ls "$CWD"/.flutter-plugins* >/dev/null 2>&1 || ls "$CWD/shiftr_ble"/.flutter-plugins* >/dev/null 2>&1; then
    fail ".flutter-plugins* presente — remover (Fase 2)"
  else
    ok "sem .flutter-plugins*"
  fi

  # .gitignore endurecido? (aceita pré-Fase-1 em shiftr_ble/)
  GI=""
  [[ -f "$CWD/.gitignore" ]] && GI="$CWD/.gitignore"
  [[ -z "$GI" && -f "$REPO_ROOT/.gitignore" ]] && GI="$REPO_ROOT/.gitignore"
  [[ -z "$GI" && -f "$CWD/shiftr_ble/.gitignore" ]] && GI="$CWD/shiftr_ble/.gitignore"
  if [[ -f "$GI" ]]; then
    for pat in ".vscode/" "tools/__pycache__/" "*.orig"; do
      grep -v '^[[:space:]]*#' "$GI" 2>/dev/null | grep -qF "$pat" && ok ".gitignore contém $pat" || fail ".gitignore sem $pat (Fase 2)"
    done
  else
    fail ".gitignore não encontrado"
  fi

  # lints endurecidos? (aceita pré-Fase-1 em shiftr_ble/)
  AO=""
  [[ -f "$CWD/analysis_options.yaml" ]] && AO="$CWD/analysis_options.yaml"
  [[ -z "$AO" && -f "$REPO_ROOT/analysis_options.yaml" ]] && AO="$REPO_ROOT/analysis_options.yaml"
  [[ -z "$AO" && -f "$CWD/shiftr_ble/analysis_options.yaml" ]] && AO="$CWD/shiftr_ble/analysis_options.yaml"
  if [[ -f "$AO" ]]; then
    grep -v '^[[:space:]]*#' "$AO" 2>/dev/null | grep -q "avoid_print.*true" && ok "analysis_options ativa avoid_print" || fail "analysis_options sem avoid_print: true (Fase 2)"
  else
    warn "analysis_options.yaml não encontrado em $AO"
  fi
}

# ---------- FASES 3-4: docs ----------
phase_docs() {
  section "DOCS — README, LICENSE, docs, CI (Fases 3-4)"
  R="$REPO_ROOT"
  [[ "$R" == "$CWD/shiftr_ble" ]] && R="$CWD"  # docs vivem na raiz do repo, não no subdir

  if [[ -f "$R/README.md" ]]; then
    if grep -qi "A new Flutter project" "$R/README.md"; then
      fail "README.md ainda é template Flutter — reescrever (Fase 3)"
    else
      ok "README.md existe e não é template"
    fi
    grep -qi "flutter run" "$R/README.md" && ok "README cita flutter run" || fail "README sem quickstart flutter run (Fase 3)"
  else
    fail "README.md ausente na raiz do repo"
  fi

  [[ -f "$R/LICENSE" || -f "$R/LICENSE.md" ]] && ok "LICENSE presente" || fail "LICENSE ausente (Fase 3, MIT)"
  [[ -f "$R/CHANGELOG.md" ]] && ok "CHANGELOG.md presente" || fail "CHANGELOG.md ausente (Fase 3)"
  [[ -f "$R/docs/protocol.md" ]] && ok "docs/protocol.md presente" || fail "docs/protocol.md ausente (Fase 3)"
  [[ -f "$R/docs/virtual_trainer.md" ]] && ok "docs/virtual_trainer.md presente" || fail "docs/virtual_trainer.md ausente (Fase 3)"
  [[ -f "$R/.github/workflows/flutter.yml" ]] && ok "CI workflow presente" || fail ".github/workflows/flutter.yml ausente (Fase 4)"
}

# ---------- FASES 5-7: code ----------
phase_code() {
  section "CODE — refactor, testes, UI (Fases 5-7)"
  LIB="$ROOT/lib"
  TEST="$ROOT/test"

  # split do god-class?
  for f in "ble_scanner.dart" "power_parser.dart" "fec_controller.dart"; do
    [[ -f "$LIB/services/$f" ]] && ok "lib/services/$f existe (Fase 5)" || fail "lib/services/$f ausente (Fase 5)"
  done
  # bugs conhecidos (heurística textual — não substitui review)
  if grep -rq "fecBytes.add" "$LIB" 2>/dev/null; then
    fail "mutação fecBytes.add ainda presente — corrigir com cópia (Fase 5)"
  else
    ok "sem mutação fecBytes.add em lib/"
  fi
  if grep -rn "print(" "$LIB" 2>/dev/null | grep -v "debugPrint" | grep -q .; then
    fail "print() ainda usado em lib/ — trocar por debugPrint/logger (Fase 5)"
  else
    ok "sem print() cru em lib/"
  fi
  if [[ -f "$LIB/core/constants.dart" ]]; then
    ok "lib/core/constants.dart existe (Fase 5)"
  else
    fail "lib/core/constants.dart ausente (Fase 5)"
  fi
  if [[ -f "$LIB/core/theme.dart" ]]; then
    ok "lib/core/theme.dart existe (Fase 7)"
  else
    fail "lib/core/theme.dart ausente (Fase 7)"
  fi

  # testes
  [[ -f "$TEST/services/power_parser_test.dart" ]] && ok "power_parser_test existe" || fail "power_parser_test ausente (Fase 6)"
  [[ -f "$TEST/services/fec_controller_test.dart" ]] && ok "fec_controller_test existe" || fail "fec_controller_test ausente (Fase 6)"
  if has_cmd flutter && [[ -f "$ROOT/pubspec.yaml" ]]; then
    echo "  -- rodando: flutter analyze --no-pub"
    if flutter analyze --no-pub 2>&1 | tail -n 5; then
      echo "  (verifique acima: 0 issues = OK)"
    fi
    echo "  -- rode manualmente: flutter test / flutter build apk --debug"
  else
    warn "flutter não encontrado ou fora do dir Flutter — pulei analyze/test automáticos"
  fi
}

# ---------- fix-clean ----------
fix_clean() {
  echo "--fix-clean: remove artefatos ignorados (build, .dart_tool, .idea, *.iml, .flutter-plugins*)"
  read -r -p "Confirmar limpeza em $CWD e $ROOT? [s/N] " ans
  [[ "$ans" == "s" || "$ans" == "S" ]] || { echo "Cancelado."; exit 1; }
  for base in "$CWD" "$ROOT" "$CWD/shiftr_ble"; do
    [[ -d "$base" ]] || continue
    rm -rf "$base/build" "$base/.dart_tool" "$base/.idea" "$base/.flutter-plugins" "$base/.flutter-plugins-dependencies"
    rm -f "$base"/*.iml
  done
  has_cmd flutter && (cd "$ROOT" && flutter clean || true)
  echo "Limpeza concluída. Rode ./checklist.sh para re-verificar."
}

# ---------- main ----------
if [[ "$FIX_CLEAN" == "1" ]]; then
  fix_clean
  exit 0
fi

echo "ShiftR checklist — root Flutter: $ROOT | repo: $REPO_ROOT | phase: $PHASE"
case "$PHASE" in
  org) phase_org ;;
  docs) phase_docs ;;
  code) phase_code ;;
  *) phase_org; phase_docs; phase_code ;;
esac

echo ""
echo "Resultado: $PASS OK, $FAIL FAIL, $WARN WARN"
[[ "$FAIL" -eq 0 ]] && { echo "Tudo certo nesta fase. ✅"; exit 0; } || { echo "Há pendências acima — siga o PLAN.md. ❌"; exit 1; }
