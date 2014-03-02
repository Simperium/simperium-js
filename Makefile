ifndef CLOSURE_COMPILER
	CLOSURE_COMPILER = closure-compiler
endif

CLOSURE_OPTS = --compilation_level SIMPLE_OPTIMIZATIONS --warning_level QUIET

LIBS = libs/jsondiff-1.0.js libs/diff_match_patch_uncompressed.js libs/sockjs-0.3.4.js

TARGETS = simperium.js simperium-dev.js

all: $(TARGETS)

simperium.js: $(LIBS) sync-nolog.js
	$(CLOSURE_COMPILER) $(addprefix --js ,$^) --js_output_file $@ $(CLOSURE_OPTS)

simperium-dev.js: $(LIBS) sync.js
	$(CLOSURE_COMPILER) $(addprefix --js ,$^) --js_output_file $@ $(CLOSURE_OPTS)

sync-nolog.js: sync.js
	# redefine console.log to strip out log calls for production
	@sed -e 's/console\.log/false\ \&\&\ console\.log/' $^ > $@

sync.js: sync.coffee
	coffee -c $^

clean:
	rm -f *.js
