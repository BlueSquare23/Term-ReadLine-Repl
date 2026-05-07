## Todos

* [x] **Fix warn message on read and write history**
  - You can tell its human generated cause I copied it outta the old script and
    forgot to change it.

* [x] **Include Github link in Build.PL/META**

* [x] **Fix help menu print to be less confusing / remove = sign**
  - Coworker pointed out the help menu print is confusing cause it prints an equal for opt args.
  - Going to make it not do that.

---

### Bugs (from code review)

* [x] **[CRITICAL] `help` check uses regex match instead of string equality (run(), line 328)**
  - `if ($input =~ 'help')` matches any input that *contains* the substring "help",
    not just the literal command `help`. This means commands like `helpful`, `gethelp`,
    or any user command whose name includes "help" will be silently intercepted and
    display the help menu instead of executing. The fix is to use string equality:
    `if ($input eq 'help')`. This is a correctness bug that would silently break any
    user-defined command with "help" anywhere in its name.

* [x] **[CRITICAL] History file grows unboundedly on every session exit (_save_history(), line 487)**
  - The file is opened with `>>` (append mode). On startup, all existing history lines
    are loaded into Term::ReadLine's in-memory history buffer via `addhistory`. On exit,
    `GetHistory()` returns the *entire* in-memory buffer — including all the entries that
    were loaded from the file — and appends them all again. This means every entry gets
    duplicated on every run. After N sessions a history file with 10 entries becomes 10*N
    lines. The fix is to open with `>` (overwrite): since `GetHistory()` already returns
    the full canonical history, overwriting gives the correct persistent-history behavior
    without accumulation.

* [x] **[CRITICAL] Passthrough strips all `!` characters instead of just the leading one (run(), line 337)**
  - `$args[0] =~ s/\!//g` uses the global `/g` flag with no anchor, so it removes every
    `!` character anywhere in the first token. For example `!echo he!lo` would execute
    `echo hello` rather than `echo he!lo`. The fix is `s/^\!//` — anchored to the start,
    no global flag — which removes only the leading `!` that signals a passthrough command.

* [ ] **[SIGNIFICANT] `exit` not injected into `cmd_schema` (new(), lines 260–261)**
  - The run loop exits on both `exit` and `quit` (line 324: `/^(exit|quit)$/`), but only
    `quit` is added to `cmd_schema`. This means `exit` never appears in the help output
    or tab completion, which contradicts the documentation ("quit/exit are injected
    automatically into every REPL"). The fix is to add
    `$self->{cmd_schema}{exit} = {}` alongside the existing `quit` injection.

* [x] **[SIGNIFICANT] `args` validation accepts any reference, not just ARRAY refs (validate_args(), line 287)**
  - `unless ref $schema->{args}` is true for *any* reference type — HASH, CODE, SCALAR,
    etc. — so the error message "args is NOT a arrayref!" would never fire for a user who
    accidentally passes a hashref or coderef as `args`. The check should be
    `unless ref $schema->{args} eq 'ARRAY'` to actually enforce the expected type.

* [ ] **[SIGNIFICANT] Deprecated array-slice syntax generates warnings in tab completion (_tab_complete(), line 428)**
  - `my $args = @{$schema->{args}}[$arg_index]` is a single-element array slice used in
    scalar context. Under `use warnings` this generates: "Scalar value
    @{$schema->{args}}[$arg_index] better written as $schema->{args}[$arg_index]". This
    warning fires every time the tab-completion function is called, so in an interactive
    session it would spam warnings into the terminal on every TAB press. The fix is to
    write it as a direct element access: `$schema->{args}[$arg_index]`.

* [ ] **[SIGNIFICANT] `_read_history` reads from filehandle even if open failed (lines 473–478)**
  - `open my $fh, '<', $file or warn "..."` only warns on failure and lets execution
    continue. At that point `$fh` is undef, and the `while (my $line = <$fh>)` loop
    immediately produces a second confusing warning ("readline() on unopened filehandle")
    before silently doing nothing. The user sees two unrelated-looking warnings for one
    problem. The fix is either to use `or die`/`or croak` so the error is hard, or to
    restructure as `if (open my $fh, ...) { ... } else { warn ... }` so the loop body
    is only reached when the open actually succeeded.

* [ ] **[MINOR] `use Data::Dumper` imported but never used (line 239)**
  - `Data::Dumper` is listed as a dependency but is never called anywhere in the module.
    It should be removed to avoid loading an unnecessary module and to keep the dependency
    list honest. Likely a leftover from development/debugging.

* [ ] **[MINOR] `Term::ReadLine->new` name hardcoded to `'Simple Shell'` (run(), line 307)**
  - `Term::ReadLine->new('Simple Shell')` ignores `$self->{name}`, which the user already
    supplied as the REPL's identity. The name passed to `Term::ReadLine::new` is used
    internally by some backends (e.g. for history separation between different REPLs on
    the same system). It should be `Term::ReadLine->new($self->{name})`.

* [ ] **[MINOR] `sort` on array of hashrefs in `_help` is meaningless (_help(), line 454)**
  - `sort @{$self->{cmd_schema}{$cmd}{args}}` sorts hashrefs using Perl's default string
    comparison, which compares the stringified reference addresses (`HASH(0x55f3a2...)`).
    These addresses are non-deterministic between runs and have no relationship to the
    arg names or their order in the schema. The sort produces unpredictable output and
    should simply be removed — the args will render in their original schema-defined order.

* [ ] **[MINOR] `eval` around `custom_logic` call silently swallows exceptions (run(), lines 356–368)**
  - The `eval { $self->{custom_logic}->(\@args) }` block captures any die/croak thrown
    by the user's callback, but `$@` is never checked afterward. If the callback dies,
    execution silently continues to the next loop iteration with no indication to the user
    or calling code that anything went wrong. At minimum, a `warn $@ if $@` after the
    eval would surface the error. Alternatively, if the intent is to let exceptions
    propagate, the eval should be removed entirely.
