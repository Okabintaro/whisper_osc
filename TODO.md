- [ ] Test and fix copyTo()
  - There was a segfault when start was < end which I though I handled
```
info: Voice lost: s:925696, e:28672
thread 113034 panic: index out of bounds

// What??
info: Voice detected! s: 18446744073709547520
info: Voice lost: s:18446744073709547520, e:57344
```
- [ ] Fix Ctrl-C
