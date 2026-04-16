from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class ReplRequest(_message.Message):
    __slots__ = ("command", "args")
    COMMAND_FIELD_NUMBER: _ClassVar[int]
    ARGS_FIELD_NUMBER: _ClassVar[int]
    command: str
    args: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, command: _Optional[str] = ..., args: _Optional[_Iterable[str]] = ...) -> None: ...

class ReplResponse(_message.Message):
    __slots__ = ("success", "output", "should_exit", "available_commands")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    OUTPUT_FIELD_NUMBER: _ClassVar[int]
    SHOULD_EXIT_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_COMMANDS_FIELD_NUMBER: _ClassVar[int]
    success: bool
    output: str
    should_exit: bool
    available_commands: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, success: bool = ..., output: _Optional[str] = ..., should_exit: bool = ..., available_commands: _Optional[_Iterable[str]] = ...) -> None: ...
