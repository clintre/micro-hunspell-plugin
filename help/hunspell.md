# Hunspell plugin

The text will be checked for misspells as you type. It understands the syntax
of XML, HTML, TeX, and Groff/Troff (Manpages). 

You need to have Hunspell installed and available in your PATH. It does not come
with this plugin. If you are on Windows, you can install Hunspell through
[MSYS2](https://www.msys2.org/).

## Options

* `hunspell.check`: controls whether spellchecking is performed. Possible values
   are `on`, `off` and `auto`. When set to `auto`, the file will be checked
   only if it's one of these filetypes: XML, HTML, TeX, Groff/Troff, or Manpage. Defaults to `auto`.

* `hunspell.dict`: dictionary to use. Run `hunspell -D` in a terminal to see
   available dictionaries. It will be passed to Hunspell in the `-d` option (e.g., `en_US`). 
   If left empty (which is the default), Hunspell will follow your system's locale settings.

* `hunspell.args`: additional command line arguments that will be passed to
   Hunspell.

When you change some of these settings while in Micro using `setlocal` or
`set`, you might not see the effect until you modify a buffer.

You can also disable or enable spellchecking for specific file types in your
`settings.json`:

```json
{
    "*.txt": {
        "hunspell.check": "on"
    },
    "ft:markdown": {
        "hunspell.check": "off"
    }
}
```

## Commands

* `togglecheck`: turns the spellchecking on/off. You can bind it to a key as
   `lua:hunspell.addpersonal`. The effect's the same as changing `hunspell.check`
   using `setlocal`.

* `addpersonal`: adds the word the cursor is on to your personal dictionary, so
   that it won't be highlighted as a misspell anymore. You can bind it to a key
   as `lua:hunspell.addpersonal`.

* `acceptsug 'n'?`: accepts the nth suggestion for the word the cursor is on.
   You can bind it to a key as `lua:hunspell.acceptsug`. If `n` is not provided or
   this command is invoked with a keyboard shortcut, it will start to cycle
   through the suggestions. Use `Tab` and `Backtab` to cycle through them.

You can also use them in chain keybindings with `,`, `&` and `|` (see
`help keybindings`). Example `bindings.json`:

```json
{
    "Tab": "Autocomplete|lua:hunspell.acceptsug|IndentSelection|InsertTab"
}
```
