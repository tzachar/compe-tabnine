# Warning

compe-tabnine is deprecated, as nvim-compe has been deprecated.
Please consider using [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
and [tzachar/cmp-tabnine](https://github.com/tzachar/cmp-tabnine).

# compe-tabnine
TabNine source for [hrsh7th/nvim-compe](https://github.com/hrsh7th/nvim-compe)

# Install

Using plug:
   ```viml
   Plug 'tzachar/compe-tabnine', { 'do': './install.sh' }
   ```

Using [Packer](https://github.com/wbthomason/packer.nvim/):
   ```viml
return require("packer").startup(
	function(use)
		use "hrsh7th/nvim-compe" --completion
		use {'tzachar/compe-tabnine', run='./install.sh', requires = 'hrsh7th/nvim-compe'}
	end
)
   ```

And later, enable the plugin:

   ```viml
	let g:compe.source.tabnine = v:true
   ```

Or, to set some options:
   ```viml
let g:compe.source.tabnine = {}
let g:compe.source.tabnine.max_line = 1000
let g:compe.source.tabnine.max_num_results = 6
let g:compe.source.tabnine.priority = 5000
" setting sort to false means compe will leave tabnine to sort the completion items
let g:compe.source.tabnine.sort = v:false
let g:compe.source.tabnine.show_prediction_strength = v:true
let g:compe.source.tabnine.ignore_pattern = ''
   ```

# Completion Behavior

In general, as TabNine is a predictive completion engine, you would normally
want TabNine to suggest completions after every keypress. In some instances this
may be either prohibitive or annoying. To work around it, you can use the
`ignore_pattern` config option. 
`ignore_pattern` is an RE specifying when not to suggest completions based on the character
before the cursor. For example, to not fire completions after an opening
bracket, set `ignore_pattern = '[(]'`. To disable this functionality, leave it
empty or set to an empty string.

# Packer Issues

Sometimes, Packer fails to install the plugin (though cloning the repo
succeeds). Until this is resolved, perform the following:
```sh
cd .local/share/nvim/site/pack/packer/start/compe-tabnine
./install.sh
```

Change `.local/share/nvim/site/pack/packer/start/compe-tabnine` to the path
Packer installs packages in your setup.
