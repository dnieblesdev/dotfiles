# Portable shell experience and adoption
Branch: `feat/portable-zsh-experience`; baseline `bf11aff`. Adopt Bash only; preserve real Zsh/Fish.
Delivery: reviewable local units, then user-authorized PR/merge; checks: isolated focused tests, real Bash probes, `make all`.

## Specs
S1. "Está autorizada exclusivamente la adopción de Bash utilizando el procedimiento reversible previamente verificado." "Si existe deriva, detente antes de modificar archivos reales." "Conserva .bash_profile intacto." "No cambies el shell predeterminado."
S2. "Conservar HISTFILE existente cuando sea válido." "Preferir historial incremental sin compartir automáticamente los comandos entre sesiones concurrentes." "Gestionar duplicados sin eliminar indiscriminadamente entradas."
S3. "Modo Emacs como valor inicial." "Búsqueda por prefijo con flechas arriba/abajo." "Preservar edición normal cuando no haya coincidencias." "No instalar history-substring-search por defecto."
S4. "La ausencia de plugins no debe romper el shell." "No descargar ni instalar plugins automáticamente." "No depender de rutas exclusivas de Arch o CachyOS." "Evitar duplicaciones al recargar .zshrc." "Cargar syntax highlighting después de los componentes que alteran widgets."
S5. "Fish mantiene Pure." "Bash mantiene el prompt del repositorio." "Mantén Starship como opción portable del repositorio, sin cargar simultáneamente Powerlevel10k." "No sustituyas Powerlevel10k en el Zsh real durante esta misión."
S6. "No copies la política agresiva de Fish a Bash o Zsh sin evidencia nueva." "Preservación de los contratos existentes de dotlink."
S7. "Realiza pruebas RED/GREEN para las capacidades nuevas." "Utiliza HOME/XDG temporales para las pruebas que puedan mutar historial, caché o configuraciones." "Realiza revisiones independientes y nativas por unidades coherentes, respetando las políticas del repositorio."
S8. "Actualiza docs/shells.md y la documentación pertinente." "No está autorizada la sustitución del .zshrc real." "Publica la rama y abre la PR." "Realiza el merge si no existen bloqueos ni cambios inesperados."

## Tasks
T1 | S1,S5 | inline live operation | done | no drift; private backup $HOME/.local/state/dotfiles-adoption/bash.am6t0ri_; real login/nonlogin PASS; profile and real Zsh unchanged; no source commit
T2 | S2,S3,S7 | delegated native-history/editing unit (context backstop) | in_progress | tests, docs, commit and review pending
T3 | S4,S5,S7 | delegated optional-integrations/prompt unit (context backstop) | pending | tests, docs, commit and review pending
T4 | S6,S7,S8 | inline + independent verification | pending | three-shell seam tests, isolated Zsh adoption, final diff and reviews pending
T5 | S8 | inline remote delivery | pending | approved scoped issue, PR/checks/merge/master sync pending

## Log
L1. Original request (verbatim):

# Misión: completar la configuración portable y la adopción de nuestros shells

Quiero cerrar la siguiente fase de nuestros dotfiles mediante una misión completa, dividida internamente en micro-slices autónomos.

Contexto:
- Fish ya funciona en CachyOS con Pure, mise y zoxide, y está administrado por dotlink.
- Bash y Zsh recibieron una estabilización portable integrada mediante PR #11.
- La adopción real de Bash está preparada y su procedimiento reversible ya fue probado.
- Zsh todavía utiliza la configuración de CachyOS, con Oh My Zsh, Powerlevel10k, plugins y keybindings.
- No queremos perder capacidades útiles ni copiar dependencias innecesarias de CachyOS.

Objetivo: cerrar Bash, implementar la experiencia portable de Zsh y verificar la convivencia de los tres shells.

Trabaja siguiendo ODD y las convenciones existentes. Ejecuta los slices de manera autónoma, con pruebas y revisiones proporcionales al riesgo.

No pidas autorización por errores mecánicos, defectos del arnés o decisiones técnicas locales ya cubiertas por estos requisitos.

## Slice 1 — Adopción real de Bash

Está autorizada exclusivamente la adopción de Bash utilizando el procedimiento reversible previamente verificado.

- Comprueba que .bashrc, .bash_profile y el repositorio no han cambiado desde el diagnóstico.
- Si existe deriva, detente antes de modificar archivos reales.
- Crea un respaldo privado, único y verificado de ambos archivos.
- Conserva .bash_profile intacto.
- Resguarda el .bashrc original y enlaza únicamente el módulo Bash con dotlink.
- Verifica el enlace y ejecuta pruebas reales de Bash interactivo, login y no-login.
- Comprueba mise, zoxide, prompt, aliases y funciones.
- Si algo falla, realiza rollback únicamente cuando puedas demostrar que no sobrescribirás archivos ajenos.

No cambies el shell predeterminado.

Registra la ruta del respaldo y el estado final.

## Slice 2 — Historial portable de Zsh

Implementa una política de historial explícita usando capacidades nativas de Zsh.

- Conservar HISTFILE existente cuando sea válido.
- Configurar HISTSIZE y SAVEHIST con valores razonables.
- Evitar pérdida de historial existente.
- Preferir historial incremental sin compartir automáticamente los comandos entre sesiones concurrentes.
- Gestionar duplicados sin eliminar indiscriminadamente entradas.
- No asumir que ignorar comandos con espacio inicial garantiza protección de secretos.

Comprueba persistencia y comportamiento entre sesiones aisladas.

## Slice 3 — Edición y keybindings de Zsh

Utiliza ZLE y mecanismos nativos.

- Modo Emacs como valor inicial.
- Búsqueda por prefijo con flechas arriba/abajo.
- Preservar edición normal cuando no haya coincidencias.
- No instalar history-substring-search por defecto.
- Evitar conflictos con widgets externos.
- Documentar los keybindings deliberados.

Prueba el comportamiento con sesiones aisladas.

## Slice 4 — Integraciones opcionales de Zsh

Incorpora de manera modular:

- zsh-autosuggestions.
- zsh-syntax-highlighting.
- Integración oficial de fzf.
- Completions existentes.
- Herramientas y helpers ya presentes.

Condiciones:
- La ausencia de plugins no debe romper el shell.
- No descargar ni instalar plugins automáticamente.
- No depender de rutas exclusivas de Arch o CachyOS.
- Permitir localizar plugins instalados mediante mecanismos portables o rutas explícitas configurables.
- Evitar duplicaciones al recargar .zshrc.
- Cargar syntax highlighting después de los componentes que alteran widgets.
- Verificar la convivencia con mise, zoxide y las funciones existentes.

Investiga y utiliza los mecanismos oficiales de las herramientas cuando corresponda.

No introduzcas un gestor de plugins salvo que demuestres una necesidad real.

## Slice 5 — Política de prompts

Conservar la experiencia actual hasta que haya una razón comprobada para cambiarla.

- Fish mantiene Pure.
- Bash mantiene el prompt del repositorio.
- Zsh utiliza un único backend de prompt.

Mantén Starship como opción portable del repositorio, sin cargar simultáneamente Powerlevel10k.

No sustituyas Powerlevel10k en el Zsh real durante esta misión.

Si es necesario ajustar el diseño de selección del prompt en Zsh, hazlo en el repositorio y prueba las alternativas aisladamente.

## Slice 6 — Compatibilidad entre shells

Verifica que las integraciones compartidas no se perjudiquen.

Incluye:
- Bash, Zsh y Fish.
- mise y zoxide reales cuando estén disponibles.
- Herramientas presentes y ausentes.
- PATH y precedencia de ejecutables.
- Selección por proyecto.
- Recargas de archivos de inicio.
- Sesiones login, no-login, interactivas y no interactivas.
- Comportamiento de prompts y completions.
- Portabilidad de rutas y ausencia de dependencias de CachyOS.
- Preservación de los contratos existentes de dotlink.

No copies la política agresiva de Fish a Bash o Zsh sin evidencia nueva.

## Slice 7 — Pruebas y revisiones

Realiza pruebas RED/GREEN para las capacidades nuevas.

Ejecuta pruebas enfocadas, make all, git diff --check y las verificaciones disponibles.

Utiliza HOME/XDG temporales para las pruebas que puedan mutar historial, caché o configuraciones.

Realiza revisiones independientes y nativas por unidades coherentes, respetando las políticas del repositorio.

No debilites pruebas para conseguir resultados verdes.

Si un requisito no puede verificarse, indícalo explícitamente.

## Slice 8 — Documentación y publicación

Actualiza docs/shells.md y la documentación pertinente.

Registra:
- Funcionalidades disponibles en cada shell.
- Dependencias opcionales.
- Keybindings.
- Política de historial.
- Selección del prompt.
- Limitaciones y riesgos residuales.
- Procedimiento de adopción y rollback de Zsh.

Mantén los cambios de Zsh en una rama específica, con commits separados por slices cuando sea útil.

Cuando los slices estén validados:
- Comprueba el diff completo contra master.
- Publica la rama y abre la PR.
- Verifica conflictos, revisiones y checks aplicables.
- Realiza el merge si no existen bloqueos ni cambios inesperados.
- Sincroniza master y verifica el árbol limpio.

No fuerces ni eludas ninguna política de revisión.

## Límites de autonomía

Está autorizada la adopción real de Bash bajo el procedimiento reversible ya aprobado.

No está autorizada la sustitución del .zshrc real. Solo puedes preparar y validar su futura adopción en entornos aislados.

No modifiques configuraciones reales de Fish, mise, CachyOS, Pure, Powerlevel10k ni Oh My Zsh.

No cambies el shell predeterminado ni instales paquetes.

Detente únicamente ante decisiones arquitectónicas importantes, riesgo de pérdida de datos, cambios de contrato o fallos que invaliden los criterios de aceptación.

Si Bash se adopta correctamente pero Zsh queda bloqueado, conserva el resultado seguro de Bash e informa del bloqueo; no mezcles las dos operaciones.

## Entrega final

Presenta:
1. Estado real de adopción de Bash y ruta del respaldo.
2. Funcionalidades implementadas en Zsh.
3. Comparación final Bash/Zsh/Fish.
4. Resultados de pruebas y revisiones.
5. Commits, PR y merge, si procede.
6. Riesgos residuales.
7. Pasos exactos pendientes para adoptar Zsh en CachyOS.

El objetivo es una experiencia de desarrollo portable y mantenible, no reproducir todos los detalles de CachyOS ni maximizar la cantidad de funcionalidades.

L3. Bash adopted safely: verified copies and retained .bashrc.original under private0700 $HOME/.local/state/dotfiles-adoption/bash.am6t0ri_. Real .bashrc -> repository bash/.bashrc; dotlink verify PASS. Actual interactive login and nonlogin startup PASS exit0/exact stdout/no stderr for mise,zoxide,dev,ll,repo PS1. Histfile /dev/null and XDG/mise state temporary/offline; no tool configuration changes. .bash_profile and real .zshrc bytes/mode/mtime unchanged; no default-shell change or rollback. Keep this result independent from any Zsh blocker.

L2. Initial drift check PASS before any writes: .bashrc SHA256959bc596166c9758fdd68836581f6b8f1d6fdb947d580bf24dce607998a077b8 and .bash_profile SHA256e149407c2bee17779caec70a7edd3d0000d172e7e4347429b80cb4d55bcec9c2, regular0644, repository clean HEADbf11aff. Real Bash operation independently authorized; other live shells unchanged. Forecast ~700 authored lines in coherent units; delivery shape subject to repository policy/user decision at PR time, no aggregate native review. Risk: item1 history persistence and item3 prompt/widget interactions; native/independent checks required. Context backstop routes bounded implementation to workers.
