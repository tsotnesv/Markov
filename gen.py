from os import environ
import sys
import random
import argparse
from dotenv import dotenv_values
from itertools import accumulate
from collections import defaultdict

def resolve_input(cli_option : int | None, name : str, env_cfg : dict[str,str | None], default: int | None) -> tuple[int | None, str]:
    if cli_option is not None:
        return cli_option, "cli"
    elif name in environ:
        return int(environ[name]), "env"
    elif name in env_cfg:
        raw = env_cfg[name]
        if raw is None:
            raise ValueError()
        return int(raw), ".env"
    return default, "default"

    
parser = argparse.ArgumentParser(
description='''reads a text from stdin and builds a 
bigram model: for every word, which words follow it and how often. Then it generates new text. 
Every output line starts from the word START given as a positional argument and continues word by word. 
The next word is chosen at random, with probability proportional to how often the pair occurs in the source text.'''
)

parser.add_argument('--lines', type=int, metavar='L')   
parser.add_argument('--width', type=int, metavar='W')
parser.add_argument('--seed', type=int, metavar='S')
parser.add_argument('--verbose', action='store_true')
parser.add_argument('--show-config', action='store_true')
parser.add_argument('START', type=str)

args = parser.parse_args()
env_cfg = dotenv_values('.env')

lines, lines_src = resolve_input(args.lines, "GEN_LINES", env_cfg, 0)
width, width_src = resolve_input(args.width, "GEN_WIDTH", env_cfg, 10)
seed, seed_src = resolve_input(args.seed, "GEN_SEED", env_cfg, None)

if args.START is None or width is None or lines is None or width <= 0 or lines < 0:
    sys.exit(2)

if args.show_config:
    sys.stdin.write(f'lines={lines} ({lines_src})\n')
    sys.stdin.write(f'width={width} ({width_src})\n')
    sys.stdin.write(f'lines={seed} ({seed_src})\n')

words = sys.stdin.read().split()
temp_dict : dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
for i in range(0,len(words)-1):
    temp_dict[words[i]][words[i+1]] += 1

table = {}
for key, followers in temp_dict.items():
    table[key] = (list(followers), list(accumulate(followers.values())))

rng = random.Random(args.seed)

while lines != 0:
    current : str = args.START
    width = args.width - 1
    sys.stdout.write(current + ' ')
    while width != 0:
        width -= 1
        if table.get(current) is None:
            break
        words, cumul = table[current]
        current = rng.choices(words,cum_weights=cumul)[0]
        sys.stdout.write(current + ' ')
    sys.stdout.write('\n')
    if args.verbose:
        sys.stderr.write('stderr output for the sake of it\n')
    lines -= 1
