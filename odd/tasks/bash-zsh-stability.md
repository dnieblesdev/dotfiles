# Bash and Zsh stabilization
Portable interactive shells without managing foreign startup files. Branch: `feat/bash-zsh-stability`.
Delivery: local reviewable commits only; PR shape deferred (no publishing authorized). Checks: focused isolated shell tests and `make all`.

## Specs
S1. "Inspecciona, de forma estrictamente read-only, los archivos necesarios para comprender los conflictos actuales de `~/.bashrc` y `~/.zshrc`, sus inclusiones directas y los archivos de login relacionados." "No leas historiales, credenciales ni otros archivos personales no necesarios. No reproduzcas secretos en los informes."
S2. "Las configuraciones específicas de máquina deben ser opcionales, explícitas o separadas de las portables." "No elimines funcionalidades existentes sin justificarlo." "Incluye pruebas de regresión para los problemas corregidos."
S3. "Investiga y estabiliza mise, zoxide y las integraciones que ya existen en Bash y Zsh." "No impongas automáticamente MISE_ACTIVATE_AGGRESSIVE ni copies los callbacks de Fish. Justifica cualquier política de precedencia."
S4. "Verifica los casos interactivo, no interactivo, login y no-login." "Mantén intactos los archivos existentes del usuario. Si una solución requiere ampliar el contrato de `dotlink` o administrar archivos adicionales de login, detén únicamente ese cambio y presenta la decisión arquitectónica."
S5. "Utiliza herramientas reales en entornos aislados cuando sea posible, con pruebas negativas y ejecutables competidores correctamente construidos." "Realiza una revisión independiente y una revisión nativa de fiabilidad, legibilidad, seguridad y portabilidad." "No debilites pruebas para conseguir resultados verdes."
S6. "Entrega una matriz comparativa de Bash, Zsh y Fish con las capacidades compartidas y las diferencias deliberadas." "Registra riesgos residuales y oportunidades futuras, sin convertirlas automáticamente en nuevas tareas."
S7. "No realices cambios en el HOME real. Trabaja en una rama específica, con commits separados por slices cuando tengan sentido." "No hagas push, PR ni merge todavía." "No declares la misión terminada si quedan criterios de aceptación sin verificar; distingue claramente los slices completos de los bloqueados."

## Tasks
T1 | S1,S4,S7 | inline + read-only explorer | done | static inventory in docs/shells.md, real entrypoints preserved; commit: 46e69be
T2 | S2,S7 | inline (one dependent portability unit) | done | RED 6 failures; GREEN 4 tests, make all, independent PASS; commit: be90051; native review in T4
T3 | S3,S5,S7 | delegated (runtime context backstop) | done | RED prior activation/NVM completion and executable-only deactivation; GREEN 7 tools tests; commits: 8a5df2a,85719a4
T4 | S4,S5 | delegated startup tests + independent verifier + native review | done | 8 startup tests, make all PASS; independent correction recheck PASS; both native authorities approved and burned; commits: 8a5df2a,85719a4
T5 | S6,S7 | delegated docs + inline closure | done | docs/shells.md matrix, links and residual limits checked; commit: 8a5df2a; final commit records closure

## Log
L1. Original request (verbatim):

# Misión: estabilizar Bash y Zsh en nuestros dotfiles

Quiero que te encargues de investigar y mejorar integralmente los módulos Bash y Zsh de nuestro repositorio de dotfiles.

Trabaja de manera autónoma, dividiendo la misión en micro-slices pequeños, verificables y con responsabilidades claras. No necesito aprobar cada slice ni cada corrección menor.

## Objetivo

Conseguir que Bash y Zsh sean portables, reproducibles y compatibles con herramientas modernas como mise y zoxide, sin sobrescribir configuraciones ajenas ni trasladar mecánicamente la arquitectura de Fish.

El resultado debe funcionar razonablemente en instalaciones limpias de Linux, preservar compatibilidad con WSL y evitar dependencias innecesarias de una distribución particular.

## Principios de ejecución

- Sigue el flujo ODD y las convenciones existentes del repositorio.
- Investiga antes de modificar.
- Evita refactorizaciones amplias que no sean necesarias.
- Cada slice debe tener un objetivo, pruebas y evidencia de cierre.
- Corrige autónomamente problemas menores del código o del arnés.
- No debilites pruebas para conseguir resultados verdes.
- No instales herramientas ni cambies el shell predeterminado.
- No alteres configuraciones reales del usuario o del sistema.
- Diferencia comportamiento comprobado, comportamiento inferido y limitaciones conocidas.
- Las revisiones independientes deben formar parte del flujo, no quedar únicamente al final.

## Slice 1 — Inventario y configuración efectiva

Investiga los entrypoints del repositorio, sus dependencias y la secuencia real de inicialización.

Inspecciona, de forma estrictamente read-only, los archivos necesarios para comprender los conflictos actuales de `~/.bashrc` y `~/.zshrc`, sus inclusiones directas y los archivos de login relacionados.

No leas historiales, credenciales ni otros archivos personales no necesarios. No reproduzcas secretos en los informes.

Determina qué configuración está realmente activa y qué pertenece únicamente al repositorio.

Entrega un mapa de dependencias, conflictos y comportamiento por tipo de sesión.

## Slice 2 — Portabilidad básica

Identifica y corrige los acoplamientos innecesarios:

- Rutas `/home/dniebles` y montajes personales.
- Dependencias de Homebrew no protegidas.
- Referencias específicas de Bun, Java, Flutter, Android y otras herramientas.
- Resolución del repositorio mediante `~/.dotfiles`.
- Suposiciones sobre utilidades instaladas.
- Diferencias entre Linux nativo y WSL.

No elimines funcionalidades existentes sin justificarlo.

Las configuraciones específicas de máquina deben ser opcionales, explícitas o separadas de las portables.

Incluye pruebas de regresión para los problemas corregidos.

## Slice 3 — Integraciones de herramientas

Investiga y estabiliza mise, zoxide y las integraciones que ya existen en Bash y Zsh.

Comprueba:
- Activación en sesiones interactivas.
- Ausencia de errores cuando una herramienta no está instalada.
- Comportamiento al recargar `.bashrc` o `.zshrc`.
- Duplicación de inicializaciones y hooks.
- Convivencia entre mise y NVM.
- Precedencia de ejecutables en PATH.
- Selección por proyecto cuando cambian las versiones.
- Coexistencia con Starship y el prompt existente.

Utiliza herramientas reales en entornos aislados cuando sea posible, con pruebas negativas y ejecutables competidores correctamente construidos.

No impongas automáticamente MISE_ACTIVATE_AGGRESSIVE ni copies los callbacks de Fish. Justifica cualquier política de precedencia.

## Slice 4 — Contrato de inicialización

Verifica los casos interactivo, no interactivo, login y no-login.

Determina qué garantías pueden ofrecer los módulos sin administrar todos los archivos de inicio.

Mantén intactos los archivos existentes del usuario. Si una solución requiere ampliar el contrato de `dotlink` o administrar archivos adicionales de login, detén únicamente ese cambio y presenta la decisión arquitectónica.

## Slice 5 — Verificación integral

Ejecuta las pruebas enfocadas y las pruebas globales disponibles.

Verifica también:
- Bash y Zsh en HOME/XDG temporales.
- Carga repetida e idempotencia donde corresponda.
- Herramientas presentes y ausentes.
- PATH y versiones por proyecto.
- Ausencia de mutaciones fuera del entorno de prueba.
- Compatibilidad de los módulos existentes de dotlink.

Realiza una revisión independiente y una revisión nativa de fiabilidad, legibilidad, seguridad y portabilidad.

Corrige los defectos detectados sin relajar los criterios de aceptación.

## Slice 6 — Documentación y entrega

Actualiza únicamente la documentación necesaria para reflejar el comportamiento comprobado, las decisiones adoptadas y las limitaciones.

Entrega una matriz comparativa de Bash, Zsh y Fish con las capacidades compartidas y las diferencias deliberadas.

Registra riesgos residuales y oportunidades futuras, sin convertirlas automáticamente en nuevas tareas.

## Autonomía y límites

Puedes avanzar de un slice al siguiente sin pedir autorización cuando las pruebas sean satisfactorias y el cambio permanezca dentro del contrato existente.

Puedes corregir errores del arnés, reorganizar pruebas y realizar refactorizaciones locales justificadas.

Detente únicamente ante:
- Riesgo de pérdida de configuración del usuario.
- Cambio importante de arquitectura o contrato.
- Necesidad de instalar o desinstalar software.
- Contradicción entre requisitos que no pueda resolverse mediante una decisión técnica local.
- Fallos relevantes que impidan demostrar seguridad o corrección.

No realices cambios en el HOME real. Trabaja en una rama específica, con commits separados por slices cuando tengan sentido.

No hagas push, PR ni merge todavía. Primero entrega la implementación completa y el informe de revisiones para nuestra evaluación final.

No declares la misión terminada si quedan criterios de aceptación sin verificar; distingue claramente los slices completos de los bloqueados.

La prioridad no es producir la mayor cantidad de cambios, sino dejar Bash y Zsh más fiables, portables y fáciles de mantener.

L3. T2 committed be90051 (264 authored lines), isolated tests and make all PASS, independent verifier mvowfpz2-3-14pp PASS incl. baseline/candidate comparison. Native portability review review-b0016f0b9e868ec2 approved and acknowledged (authority burned). Local review slices: inventory 46e69be (211 lines), portability be90051 (264), integrations/startup 8a5df2a (464; cohesive code+tests+docs moderately exceeds the advisory 400), bounded native correction 85719a4 (30). PR shape deferred: no publishing requested; never treat the accumulated feature as one native candidate. Runtime context backstop routed T3 and startup/docs to bounded workers. Closure synchronizes the full Engram document mirror; the earlier recovery copy held only locator and task state.

L4. Integration checks: real mise 2026.10.19, zoxide 0.10.0 and Starship; allowlist PATH negative tests. Synthetic NVM executable competes with local-bin node, real path-backend projects A/B assert executable and env A:A/B:B/A:A, single hooks, preserved prompt and user PATH entries. Independent verifier mvox5ofn-7-qgn4 exposed actual prior-activation precedence and wrong __nvm completion guard; one correction batch and limited recheck mvoxkrza-9-5duf PASS. Native four-lens review review-ebc0152e3976f108 + refuter required R3-001 correction; eval of command mise deactivate now handles both function-backed and executable-only paths. Correction 30 diff lines within plan80; native targeted validator approved, exact acknowledgement burned authority on corrected target sha256:c5cb1ae21991d9a51654319aad916148d85e5b810aaa1f963a166b373afea92f.
L5. Final checks: python3 dotlink/tests/shells.py (8 PASS), shells-tools.py (7 PASS), make all PASS (worker final correction and parent prior full run); diff checks PASS. Tests never install tools or use actual user startup execution. Real .bashrc/.zshrc/.bash_profile bytes compared to initial authorized read and unchanged. Existing dotlink tests and additional Zsh conflict assert exact exit/stdout/stderr and unchanged synthetic user/login files. Base/candidate aliases/env comparisons match outside requested changes. Actual WSL is not available: test wrapper simulates /proc/version detector; real NVM unavailable: synthetic fixture only. Login profiles remain user-owned, explicit-source matrix is not host-distro certification. No architecture/dotlink ownership expansion, no publishing. Residual guard coupling to generated mise/zoxide/NVM/Starship hooks documented; no future tasks automatically opened. Risk: item 3 (shared environment and prompt reload consumers); independent and native reviews completed.

L2. Baseline da4b4c5, clean master; created feat/bash-zsh-stability. Forecast ~700 authored lines across independent reviewable local commit slices, not one PR. No PR decision needed until delivery is requested. Risk: item 3 (shared environment helpers affect both shells). Writer delegation does not fire: portability and integration depend on the same startup chain; work inline. Read-only explorer traced external startup without executing it.
