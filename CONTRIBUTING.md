# Contributing to Tide Island Extended

Thank you for your interest in contributing to **Tide Island Extended**! We welcome bug reports, design ideas, optimizations, and pull requests.

---

## Code of Conduct & Guidelines

1. **Focused Topics**: Please keep each issue or pull request focused on one specific topic or feature.
2. **Discuss First**: For substantial UI changes or new feature architectures, please open an issue or discussion first to align on direction.
3. **Compositor Compatibility**: Tide Island is designed for modern Wayland compositors, with official focus on **Hyprland** and **niri**. Please verify that your changes maintain stability across both where applicable.

---

## Development Setup

### 1. Fork & Clone
```bash
git clone https://github.com/<your-username>/Tide-island-extended.git
cd Tide-island-extended
```

### 2. Install Dependencies
Run the built-in dependency check:
```bash
./install.sh --check-deps
```

### 3. Build Locally
```bash
# Configure build directory
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

# Build binaries and backend plugins
cmake --build build --parallel

# Run unit tests
ctest --test-dir build --output-on-failure
```

---

## Submitting Pull Requests

1. Create a descriptive feature branch from `main` (or `beta`):
   ```bash
   git checkout -b feature/my-enhancement
   ```
2. Verify that your code compiles cleanly without warnings and passes all tests:
   ```bash
   ctest --test-dir build --output-on-failure
   ```
3. Test your changes locally on your desktop to ensure no visual regressions, animation stutter, or unintended CPU/memory overhead.
4. Commit your changes with clear, structured commit messages (e.g., `fix(equalizer): ...`, `feat(screen-recorder): ...`, `docs: ...`).
5. Open a Pull Request on GitHub against `main` using the PR template.
