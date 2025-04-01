import itertools
from .common import AsyncLLM, Message, TextRaw, ToolUse, ThinkingBlock


def merge_text(content: list[TextRaw | ToolUse | ThinkingBlock]) -> list[TextRaw | ToolUse | ThinkingBlock]:
    merged = []
    for k, g in itertools.groupby(content, lambda x: isinstance(x, TextRaw)):
        if k and (text := "".join([x.text for x in g])) != "":
            merged.append(TextRaw(text))
        else:
            merged.extend(g)
    return merged


async def loop_completion(m_client: AsyncLLM, messages: list[Message], **kwargs) -> Message:
    content: list[TextRaw | ToolUse | ThinkingBlock] = []
    while True:
        payload = messages + [Message(role="assistant", content=content)] if content else messages
        completion = await m_client.completion(messages=payload, **kwargs)
        content.extend(completion.content)
        if completion.stop_reason != "max_tokens":
            break
    return Message(role="assistant", content=merge_text(content))
