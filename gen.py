import sys
import random
import argparse
from os import environ
from itertools import accumulate
from collections import defaultdict

from dotenv import dotenv_values # hopefully the only external thing

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

def generate():
    
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

    try:
        lines, lines_src = resolve_input(args.lines, "GEN_LINES", env_cfg, 0)
        width, width_src = resolve_input(args.width, "GEN_WIDTH", env_cfg, 10)
        seed, seed_src = resolve_input(args.seed, "GEN_SEED", env_cfg, None)
    except ValueError:
        parser.error("Nice try")
    
    if width is None or lines is None:
        parser.error("Width or Lines not found")
        # Yeah though they have default values. This line just exists for those two to be explicitly ints
    if width <= 0:
        parser.error("Width limit must be a positive integer")
    if lines < 0:
        parser.error("Line count must be a non-negative integer")
        
    if args.show_config:
        sys.stdout.write(f'lines={lines} ({lines_src})\n')
        sys.stdout.write(f'width={width} ({width_src})\n')
        sys.stdout.write(f'seed={"None" if seed is None else seed} ({seed_src})\n')
        sys.exit(0)

    words = sys.stdin.read().split()
    if args.START not in words: # Also checks if the input is non-empty
        sys.stderr.write("START must be present in the text")
        sys.exit(1)
        
    temp_dict : dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for i in range(0,len(words)-1):
        temp_dict[words[i]][words[i+1]] += 1

    table = {}
    for key, followers in temp_dict.items():
        table[key] = (list(followers), list(accumulate(followers.values())))
        
    pair_cnt = sum(len(i) for i in temp_dict.values())
    sys.stderr.write(f"Random stat to act as a filler for stderr:\nTotal number of distinct pairs are {pair_cnt}\n")

    rng = random.Random(seed)

    if lines == 0:
        lines = -1

    while lines != 0:
        lines -= 1
        current : str = args.START
        width_tmp = width - 1
        sys.stdout.write(current + ' ')
        while width_tmp != 0:
            width_tmp -= 1
            if table.get(current) is None:
                break
            words, cumul = table[current]
            current = rng.choices(words,cum_weights=cumul)[0]
            sys.stdout.write(current + ' ')
            
        sys.stdout.write('\n')
        if args.verbose:
            sys.stderr.write('Mandatory stderr line\n')

if __name__ == "__main__":
    generate()