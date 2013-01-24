simperium-js
==============
Simperium is a simple way for developers to move data as it changes, instantly and automatically. This is the Javascript library. You can [browse the documentation](https://simperium.com/docs/js/).

You can [sign up](https://simperium.com) for a hosted version of Simperium. There are Simperium libraries for [other languages](https://simperium.com/overview/) too.

### License
The Simperium Javascript library is available for free and commercial use under the MIT license.

### Building

You'll need [coffeescript](http://coffeescript.org/) to build this project.

To use the included Makefile, set the environment variable `CLOSURE_COMPILER` to
execute Google's [Closure Compiler](http://code.google.com/p/closure-compiler/) jar:

    export CLOSURE_COMPILER="java -jar
    ~/usr/local/closure-compiler/build/compiler.jar"

By default it will try to run the command `closure-compiler` which should be
available if you use [Homebrew](https://github.com/mxcl/homebrew) to install
Google Closure Compiler.


### Getting Started

See the [introduction](https://simperium.com/docs/js/) or the [API
reference](https://simperium.com/docs/reference/js/).
