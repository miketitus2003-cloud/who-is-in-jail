#!/usr/bin/env bash
# setup.sh — Bootstrap the full project from scratch.
# Run once after cloning. Then use run.sh for subsequent pipeline runs.

set -euo pipefail

echo ""
echo "=================================================="
echo " Who Is in Jail — And Why?"
echo " Project Setup"
echo "=================================================="
echo ""

# ── 1. Python environment ──────────────────────────────────────────────────────
echo "[1/5] Setting up Python environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "      Virtual environment created."
fi
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
echo "      Dependencies installed."

# ── 2. Environment file ────────────────────────────────────────────────────────
echo "[2/5] Checking .env..."
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo ""
    echo "      .env created from .env.example."
    echo "      *** STOP — open .env and add your API tokens before continuing. ***"
    echo "      Get free tokens at:"
    echo "        NYC:    data.cityofnewyork.us"
    echo "        LA:     data.lacity.org"
    echo "        MD:     opendata.maryland.gov"
    echo "        Census: api.census.gov/sign-up.html"
    echo ""
    echo "      Also generate your PII salt:"
    echo "        python3 -c \"import secrets; print(secrets.token_hex(32))\""
    echo "      and paste it into PII_SALT= in .env"
    echo ""
    read -p "      Press Enter when .env is ready..."
else
    echo "      .env already exists — skipping."
fi

# ── 3. Data directory ──────────────────────────────────────────────────────────
echo "[3/5] Creating data directory..."
mkdir -p data
echo "      data/ ready (not tracked by git)."

# ── 4. PostgreSQL database ────────────────────────────────────────────────────
echo "[4/5] Setting up PostgreSQL..."
source .env 2>/dev/null || true
DB_NAME="${DB_NAME:-jail_data}"
DB_USER="${DB_USER:-postgres}"

if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "      Database '$DB_NAME' already exists."
else
    createdb -U "$DB_USER" "$DB_NAME"
    echo "      Database '$DB_NAME' created."
fi

echo "      Loading schema..."
psql -U "$DB_USER" -d "$DB_NAME" -f sql/schema/ddl.sql -q
echo "      Loading charge taxonomy..."
psql -U "$DB_USER" -d "$DB_NAME" -f sql/seeds/charge_taxonomy.sql -q
echo "      Database ready."

# ── 5. Done ────────────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Setup complete."
echo ""
echo "=================================================="
echo " Next steps:"
echo ""
echo "  1. Run the ETL pipeline:"
echo "       source venv/bin/activate"
echo "       python etl/pipeline.py"
echo ""
echo "  2. Load into PostgreSQL:"
echo "       python etl/db_loader.py"
echo ""
echo "  3. Run analysis queries:"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/innocence.sql"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/bail_gap.sql"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/plea_pressure.sql"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/addiction.sql"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/md_reform.sql"
echo "       psql -U $DB_USER -d $DB_NAME -f sql/queries/conditions.sql"
echo ""
echo "  See viz/story.md for visualization specs."
echo "=================================================="
echo ""
