import discord
from config import (
    PRIMEZ_COLOR_PRIMARY,
    PRIMEZ_COLOR_SUCCESS,
    PRIMEZ_COLOR_ERROR,
    PRIMEZ_COLOR_INFO
)

def make_primez_embed(
    title: str,
    description: str | None = None,
    color: int = PRIMEZ_COLOR_PRIMARY
) -> discord.Embed:
    """Create a stylized PRIMEz Reverser embed."""
    embed = discord.Embed(
        title=f"⚡ {title}",
        description=description,
        color=discord.Color(color)
    )
    embed.set_footer(
        text="PRIMEz Reverser • Autonomous Deobfuscation Kernel",
        icon_url="https://raw.githubusercontent.com/phantom0001-coder/PRIMEz-HUB/main/assets/primez-logo.png"
    )
    return embed

class BackendSelect(discord.ui.Select):
    def __init__(self, current_choice: str = "auto"):
        options = [
            discord.SelectOption(
                label="Auto-Detect",
                value="auto",
                description="Detect obfuscator using structural & Jaccard signatures",
                emoji="🔎",
                default=(current_choice == "auto")
            ),
            discord.SelectOption(
                label="IronBrew 1",
                value="ib1",
                description="Luau memory hook & AST reconstruction",
                emoji="1️⃣",
                default=(current_choice == "ib1")
            ),
            discord.SelectOption(
                label="IronBrew 2 / AztupBrew",
                value="ib2",
                description="Native C# bytecode disassembler",
                emoji="2️⃣",
                default=(current_choice == "ib2")
            ),
            discord.SelectOption(
                label="IronBrew 3",
                value="ib3",
                description="Pure-Python varint & prototype lifter",
                emoji="3️⃣",
                default=(current_choice == "ib3")
            ),
            discord.SelectOption(
                label="LuaObfuscator",
                value="luaobf",
                description="Symbolic execution, IR & CFG deflattener",
                emoji="🧪",
                default=(current_choice == "luaobf")
            ),
            discord.SelectOption(
                label="Luraph v14/v15",
                value="luraph",
                description="Luau behavioral sandbox & symbolic tracer",
                emoji="🛡️",
                default=(current_choice == "luraph")
            ),
        ]
        super().__init__(
            placeholder="Choose deobfuscation backend...",
            min_values=1,
            max_values=1,
            options=options,
            row=0
        )

    async def callback(self, interaction: discord.Interaction):
        self.view.selected_backend = self.values[0]
        for opt in self.options:
            opt.default = (opt.value == self.view.selected_backend)
        await interaction.response.edit_message(view=self.view)

class DeobfActionView(discord.ui.View):
    def __init__(self, owner_id: int, on_run_callback):
        super().__init__(timeout=300)
        self.owner_id = owner_id
        self.selected_backend = "auto"
        self.on_run_callback = on_run_callback
        self.add_item(BackendSelect(self.selected_backend))

    @discord.ui.button(label="Deobfuscate", style=discord.ButtonStyle.danger, emoji="▶️", row=1)
    async def run_button(self, interaction: discord.Interaction, button: discord.ui.Button):
        if interaction.user.id != self.owner_id:
            await interaction.response.send_message("❌ This session belongs to another user.", ephemeral=True)
            return
        await self.on_run_callback(interaction, self.selected_backend)
