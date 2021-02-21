# compe-tabnine
TabNine source for hrsh7th/nvim-compe

# Install

Add the following to your .vimrc:

   ```viml
   Plug 'tzachar/compe-tabnine', { 'do': './install.sh' }
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
   ```

