ifndef CLOSURE_COMPILER
	CLOSURE_COMPILER = closure-compiler
endif

CLOSURE_OPTS = --compilation_level SIMPLE_OPTIMIZATIONS --warning_level QUIET

LIBS = libs/jsondiff.js libs/diff_match_patch_uncompressed.js libs/sockjs-0.3.4.js

simperium.js: $(LIBS) sync.js
	$(CLOSURE_COMPILER) $(addprefix --js ,$^) --js_output_file $@ $(CLOSURE_OPTS)

sync.js: sync.coffee
	coffee -c $^

clean:
	rm -f *.js
