# Third-party notices

The application uses Flutter 3.47.4 (BSD 3-Clause), file_selector 1.1.0 and its platform packages (BSD 3-Clause, Flutter Authors), and exif 3.3.0 (MIT, copyright 2021 bigflood). Transitive packages and exact versions are listed in pubspec.lock. Each package's LICENSE file contains its full terms and copyright notices. Flutter collects registered package licenses into the application's license registry; distributors must retain the applicable notices and review the licenses for the exact resolved build. The Flutter SDK license is available at https://github.com/flutter/flutter/blob/master/LICENSE.

EXIF MIT license:

```
MIT License

Copyright (c) 2021 bigflood

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

file_selector BSD 3-Clause license:

```
Copyright 2013 The Flutter Authors

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

```

Additional direct Dart dependencies: `desktop_drop` 0.7.1 (Apache-2.0), `ffi` 2.2.0 (BSD 3-Clause), `path_provider` 2.1.6 (BSD 3-Clause), `window_manager` 0.5.2 (MIT), and `screen_retriever` 0.2.2 (MIT).

Direct native dependencies, all MIT OR Apache-2.0, include locally patched and vendored `c2pa` / c2pa-rs 0.91.10, `reqwest` 0.12.28, `base64` 0.22.1, `rasn` 0.28.15, `rasn-ocsp` 0.28.15, and `serde_json` 1.0.154. Exact Dart and Rust transitive versions are recorded in `pubspec.lock` and `native/c2pa/Cargo.lock`; each retains its own license. Distributors must review and include applicable notices for the resolved native dependencies and any system libraries before redistribution; the Flutter license registry does not cover Rust dependencies.
