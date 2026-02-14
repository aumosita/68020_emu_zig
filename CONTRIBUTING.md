# Contributing to 68020_emu_zig

Thank you for your interest in contributing to this project! This guide will help you get started.

## Code of Conduct

Be respectful and constructive. We're all here to build something great together.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/68020_emu_zig.git
   cd 68020_emu_zig
   ```
3. **Set up the development environment**:
   - Install Zig 0.13.x from https://ziglang.org/download/
   - Verify installation: `zig version`

## Development Workflow

### 1. Create a Branch

Create a feature branch from `main`:

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

Branch naming conventions:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation improvements
- `refactor/` - Code refactoring
- `test/` - Test additions or improvements

### 2. Make Your Changes

- Write clear, readable code
- Follow the existing code style (see `.editorconfig`)
- Add tests for new functionality
- Update documentation as needed

### 3. Test Your Changes

Run the full test suite before submitting:

```bash
# Run all tests
zig build test

# Run specific module tests
zig test src/core/cpu.zig
zig test src/core/memory.zig

# Build all examples
zig build
```

All tests must pass before your PR can be merged.

### 4. Commit Your Changes

We follow conventional commit messages:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions or changes
- `refactor`: Code refactoring (no functional changes)
- `perf`: Performance improvements
- `chore`: Build process or auxiliary tool changes

**Examples:**

```
feat(cpu): Add support for BKPT instruction

Implement BKPT breakpoint instruction with debugger hook
support. Falls back to vector 4 when no debugger is attached.

Closes #42
```

```
fix(memory): Correct alignment check for word access

Previously allowed word access on odd addresses in some cases.
Now properly raises AddressError for all misaligned accesses.

Fixes #56
```

```
docs(readme): Update build instructions for Windows

Added WSL setup instructions and corrected Zig version
requirement.
```

**Commit Guidelines:**
- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 72 characters
- Reference issues and PRs in the footer when applicable

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub with:
- Clear title following commit conventions
- Description of what changed and why
- Reference to related issues
- Screenshots/output for UI or behavior changes

## Coding Standards

### Zig Style

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Prefer 100-120 characters, hard limit at 120
- **Naming**:
  - Types: `PascalCase` (e.g., `M68k`, `Memory`)
  - Functions: `camelCase` (e.g., `executeInstruction`, `readMemory`)
  - Constants: `SCREAMING_SNAKE_CASE` (e.g., `MAX_MEMORY_SIZE`)
  - Variables: `snake_case` (e.g., `instruction_count`, `addr`)

### Documentation

- Add doc comments (`///`) for public functions and types
- Explain complex algorithms with inline comments
- Update relevant markdown docs when changing behavior

**Example:**

```zig
/// Read a byte from memory at the specified address.
///
/// Returns `InvalidAddress` if addr >= memory_size.
/// Returns `AddressError` if alignment check fails.
/// Returns `BusError` if bus hook reports an error.
pub fn read8(addr: u32) MemoryError!u8 {
    // Implementation...
}
```

### Testing

- Write tests for new features and bug fixes
- Use descriptive test names
- Test both success and error paths

**Example:**

```zig
test "read8 returns InvalidAddress for out-of-bounds access" {
    var mem = try Memory.init(allocator, .{ .size = 1024 });
    defer mem.deinit();
    
    const result = mem.read8(2048);
    try testing.expectError(error.InvalidAddress, result);
}

test "read8 returns correct value for valid address" {
    var mem = try Memory.init(allocator, .{ .size = 1024 });
    defer mem.deinit();
    
    try mem.write8(100, 0x42);
    const value = try mem.read8(100);
    try testing.expectEqual(@as(u8, 0x42), value);
}
```

## Areas for Contribution

We welcome contributions in these areas:

### High Priority
- **Error handling improvements**: Migrate internal code to structured error types
- **Performance optimization**: Arena allocators, memory pooling
- **Test coverage**: Add tests for edge cases and error paths
- **Documentation**: Improve existing docs, add examples

### Medium Priority
- **Platform support**: macOS testing and CI
- **Examples**: Real-world usage examples (game emulation, OS boot)
- **Tooling**: GDB stub, trace logging, debugger integration

### Low Priority
- **Advanced features**: PMMU full implementation, DMA simulation
- **Optimizations**: Translation cache, JIT compilation (future)

## Questions?

- Open an issue for questions about the codebase
- Check existing issues and PRs before starting work
- Feel free to ask for clarification on anything

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🎉
