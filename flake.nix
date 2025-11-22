{
  description = "Juisys - Privacy-First, GDPR-Compliant Application Auditing & Migration Planning";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = false; # FOSS only
        };

        # Julia with project dependencies
        julia = pkgs.julia-bin;

        # Optional dependencies
        gtkSupport = false; # Set to true if GTK.jl GUI desired
        diagnosticsSupport = false; # Set to true for D diagnostics add-on

        # Build inputs
        buildInputs = with pkgs; [
          julia
          git
          just # justfile runner
        ] ++ pkgs.lib.optionals gtkSupport [
          gtk3
          glib
          gobject-introspection
        ] ++ pkgs.lib.optionals diagnosticsSupport [
          ldc # D compiler for diagnostics
        ];

        # Development inputs
        nativeBuildInputs = with pkgs; [
          pkg-config
        ];

      in
      {
        # Default package
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "juisys";
          version = "1.0.0";

          src = ./.;

          inherit buildInputs nativeBuildInputs;

          # Julia package instantiation
          buildPhase = ''
            export JULIA_DEPOT_PATH=$out/share/julia
            export JULIA_PROJECT=$src
            ${julia}/bin/julia --project=$src -e 'using Pkg; Pkg.instantiate()'
          '';

          # Installation
          installPhase = ''
            mkdir -p $out/bin $out/share/juisys

            # Copy source files
            cp -r src $out/share/juisys/
            cp -r data $out/share/juisys/
            cp -r tools $out/share/juisys/
            cp -r examples $out/share/juisys/
            cp -r test $out/share/juisys/
            cp -r benchmarks $out/share/juisys/

            # Copy configuration
            cp Project.toml $out/share/juisys/

            # Copy documentation
            cp README.md QUICKSTART.md TUTORIAL.md $out/share/juisys/
            cp CONTRIBUTING.md CODE_OF_CONDUCT.md $out/share/juisys/
            cp SECURITY.md MAINTAINERS.md CHANGELOG.md $out/share/juisys/
            cp LICENSE $out/share/juisys/

            # Copy .well-known
            mkdir -p $out/share/juisys/.well-known
            cp .well-known/* $out/share/juisys/.well-known/

            # Create wrapper scripts
            cat > $out/bin/juisys <<EOF
            #!/usr/bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia -e 'include("$out/share/juisys/src/cli.jl"); CLI.run()'
            EOF
            chmod +x $out/bin/juisys

            cat > $out/bin/juisys-no-peek <<EOF
            #!/usr/bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia -e 'include("$out/share/juisys/src/cli.jl"); CLI.run_no_peek_mode()'
            EOF
            chmod +x $out/bin/juisys-no-peek

            cat > $out/bin/juisys-plan <<EOF
            #!/usr/bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia $out/share/juisys/tools/migration_planner.jl "\$@"
            EOF
            chmod +x $out/bin/juisys-plan

            cat > $out/bin/juisys-compare <<EOF
            #!/usr/bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia $out/share/juisys/tools/compare_alternatives.jl "\$@"
            EOF
            chmod +x $out/bin/juisys-compare

            cat > $out/bin/juisys-report <<EOF
            #!/usr/bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia $out/share/juisys/tools/generate_html_report.jl "\$@"
            EOF
            chmod +x $out/bin/juisys-report

            cat > $out/bin/juisys-stats <<EOF
            #!/usr:bin/env bash
            export JULIA_PROJECT=$out/share/juisys
            exec ${julia}/bin/julia $out/share/juisys/examples/example_database_stats.jl
            EOF
            chmod +x $out/bin/juisys-stats
          '';

          # Metadata
          meta = with pkgs.lib; {
            description = "Privacy-First, GDPR-Compliant Application Auditing & Migration Planning";
            homepage = "https://github.com/Hyperpolymath/jusys";
            license = licenses.mit;
            maintainers = [ "Hyperpolymath" ];
            platforms = platforms.unix;
          };
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          shellHook = ''
            echo "Juisys Development Environment"
            echo "=============================="
            echo ""
            echo "Julia version: $(julia --version)"
            echo "Just version: $(just --version)"
            echo ""
            echo "Quick start:"
            echo "  just install    # Install Julia dependencies"
            echo "  just test       # Run tests"
            echo "  just run        # Run Juisys CLI"
            echo "  just --list     # Show all commands"
            echo ""
            echo "Privacy guarantee: 100% local processing, zero network calls"
            echo ""

            # Set up Julia environment
            export JULIA_PROJECT=$PWD
            export JULIA_DEPOT_PATH=$PWD/.julia-env

            # Install dependencies on first run
            if [ ! -d ".julia-env" ]; then
              echo "Installing Julia dependencies..."
              julia --project=. -e 'using Pkg; Pkg.instantiate()'
              echo "✓ Dependencies installed"
              echo ""
            fi
          '';
        };

        # Apps for nix run
        apps = {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys";
          };

          no-peek = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys-no-peek";
          };

          plan = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys-plan";
          };

          compare = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys-compare";
          };

          report = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys-report";
          };

          stats = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/juisys-stats";
          };
        };

        # Checks (run with: nix flake check)
        checks = {
          # Run all Julia tests
          tests = pkgs.stdenv.mkDerivation {
            name = "juisys-tests";
            src = ./.;
            inherit buildInputs nativeBuildInputs;

            buildPhase = ''
              export JULIA_PROJECT=$src
              ${julia}/bin/julia --project=$src -e 'using Pkg; Pkg.instantiate()'
            '';

            checkPhase = ''
              ${julia}/bin/julia --project=$src test/runtests.jl
            '';

            installPhase = ''
              mkdir -p $out
              echo "All tests passed" > $out/result
            '';

            doCheck = true;
          };

          # Privacy compliance check
          privacy = pkgs.stdenv.mkDerivation {
            name = "juisys-privacy-check";
            src = ./.;
            inherit buildInputs nativeBuildInputs;

            buildPhase = ''
              export JULIA_PROJECT=$src
              ${julia}/bin/julia --project=$src -e 'using Pkg; Pkg.instantiate()'
            '';

            checkPhase = ''
              ${julia}/bin/julia --project=$src -e 'include("test/test_privacy.jl")'
            '';

            installPhase = ''
              mkdir -p $out
              echo "Privacy compliance verified" > $out/result
            '';

            doCheck = true;
          };

          # Database integrity check
          database = pkgs.stdenv.mkDerivation {
            name = "juisys-database-check";
            src = ./.;
            inherit buildInputs nativeBuildInputs;

            buildPhase = ''
              export JULIA_PROJECT=$src
              ${julia}/bin/julia --project=$src -e 'using Pkg; Pkg.instantiate()'
            '';

            checkPhase = ''
              ${julia}/bin/julia --project=$src test/test_database.jl
            '';

            installPhase = ''
              mkdir -p $out
              echo "Database integrity verified" > $out/result
            '';

            doCheck = true;
          };

          # RSR compliance verification
          rsr-compliance = pkgs.stdenv.mkDerivation {
            name = "juisys-rsr-compliance";
            src = ./.;

            buildPhase = ''
              # Check required files exist
              test -f README.md || (echo "Missing README.md" && exit 1)
              test -f LICENSE || (echo "Missing LICENSE" && exit 1)
              test -f CONTRIBUTING.md || (echo "Missing CONTRIBUTING.md" && exit 1)
              test -f SECURITY.md || (echo "Missing SECURITY.md" && exit 1)
              test -f CODE_OF_CONDUCT.md || (echo "Missing CODE_OF_CONDUCT.md" && exit 1)
              test -f MAINTAINERS.md || (echo "Missing MAINTAINERS.md" && exit 1)
              test -f CHANGELOG.md || (echo "Missing CHANGELOG.md" && exit 1)

              # Check .well-known
              test -f .well-known/security.txt || (echo "Missing .well-known/security.txt" && exit 1)
              test -f .well-known/ai.txt || (echo "Missing .well-known/ai.txt" && exit 1)
              test -f .well-known/humans.txt || (echo "Missing .well-known/humans.txt" && exit 1)

              # Check build system
              test -f justfile || (echo "Missing justfile" && exit 1)
              test -f flake.nix || (echo "Missing flake.nix" && exit 1)
            '';

            installPhase = ''
              mkdir -p $out
              echo "RSR compliance verified" > $out/result
            '';
          };
        };

        # Formatter (for nix fmt)
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
