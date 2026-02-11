# Python 연동 예시

아래는 `ctypes`로 공유 라이브러리를 호출하는 최소 예시입니다.

```python
import ctypes

lib = ctypes.CDLL('./zig-out/lib/libm68020-emu.dylib')

lib.m68k_create.restype = ctypes.c_void_p
cpu = lib.m68k_create()

lib.m68k_set_reg_d(cpu, 0, 0x42)
lib.m68k_set_pc(cpu, 0x1000)
lib.m68k_write_memory_16(cpu, 0x1000, 0x4E71)  # NOP

cycles = lib.m68k_step(cpu)
print('cycles =', cycles)
print('pc =', hex(lib.m68k_get_pc(cpu)))

lib.m68k_destroy(cpu)
```

## 권장 확인 항목

- `argtypes/restype`를 함수별로 정확히 지정
- 에뮬레이터 생성/해제 쌍 유지
- 바이너리 로드 후 `PC`, `SP`, 벡터 테이블 초기화 순서 점검
